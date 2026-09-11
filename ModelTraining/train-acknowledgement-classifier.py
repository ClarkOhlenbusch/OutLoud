# /// script
# requires-python = ">=3.11,<3.12"
# dependencies = ["torch==2.5.1", "transformers==4.46.3", "coremltools==8.3.0", "numpy==1.26.4"]
# ///
"""Fine-tune locally, export, then gate the exact Swift/Core ML decision."""

import argparse
import subprocess
import tempfile
import hashlib
import os

os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
import json, random, time, re
from pathlib import Path
import numpy as np
import torch
from transformers import BertTokenizer, BertForSequenceClassification
from torch.utils.data import DataLoader, TensorDataset

random.seed(8241)
np.random.seed(8241)
torch.manual_seed(8241)
torch.set_num_threads(4)
root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
modes = parser.add_mutually_exclusive_group()
modes.add_argument("--calibration-only", type=Path, metavar="DIRECTORY")
modes.add_argument("--promote", type=Path, metavar="DIRECTORY")
modes.add_argument("--check-data", action="store_true")
args = parser.parse_args()
workspace = tempfile.TemporaryDirectory(prefix="outloud-training-")
evaluator = Path(workspace.name) / "evaluate"
subprocess.run(
    [
        "xcrun",
        "swiftc",
        "-O",
        *[
            str(root / "Shared" / name)
            for name in [
                "PhraseMatcher.swift",
                "AcknowledgementDecision.swift",
                "AcknowledgementTokenizer.swift",
                "AcknowledgementInference.swift",
            ]
        ],
        str(root / "ModelTraining/evaluate-acknowledgement-classifier.swift"),
        "-o",
        str(evaluator),
    ],
    check=True,
)
subprocess.run([str(evaluator), "--check-data"], check=True)
if args.check_data:
    raise SystemExit(0)
if args.promote:
    subprocess.run(
        [
            str(evaluator),
            "--promote",
            str(args.promote / "candidate.mlmodel"),
            str(args.promote / "vocab.txt"),
        ],
        check=True,
    )
    raise SystemExit(0)
out = args.calibration_only or Path(workspace.name) / "candidate"
out.mkdir(parents=True, exist_ok=True)
if out.resolve() == (root / "OutLoud/Models").resolve():
    raise ValueError(
        "Use a separate candidate directory; shipping assets change only after evaluation."
    )
name = "sentence-transformers/all-MiniLM-L6-v2"
rev = "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"
tok = BertTokenizer.from_pretrained(name, revision=rev)
model = BertForSequenceClassification.from_pretrained(
    name, revision=rev, num_labels=2, attn_implementation="eager"
)


def corpus(split):
    data = json.loads(
        (root / f"ModelTraining/acknowledgement-{split}.json").read_text()
    )
    return [
        (s, int(k == "acknowledges"))
        for k in ["other", "acknowledges"]
        for s in data[k]
    ]


training_fingerprints = {
    split: hashlib.sha256(
        (root / f"ModelTraining/acknowledgement-{split}.json").read_bytes()
    ).hexdigest()
    for split in ["training", "calibration"]
}
train = corpus("training")
cal = corpus("calibration")


def normalized_input(text):
    for pattern, replacement in [
        (r"\bi['’]m\b", "I am"),
        (r"\bisn['’]t\b", "is not"),
        (r"\bdon['’]t\b", "do not"),
        (r"\bcan['’]t\b", "cannot"),
        (r"\bwon['’]t\b", "will not"),
    ]:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text.strip()


# Train and evaluate complete inputs, never clipped text.
def encode(rows):
    assert all(
        not any(
            marker in s for marker in ["[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]"]
        )
        for s, y in rows
    )
    data = tok(
        [normalized_input(s) for s, y in rows],
        padding="max_length",
        max_length=128,
        truncation=False,
        return_tensors="pt",
    )
    assert data["input_ids"].shape[1] == 128
    return TensorDataset(
        data["input_ids"], data["attention_mask"], torch.tensor([y for s, y in rows])
    )


# Verify the production Swift normalization/tokenizer against the trainer,
# including punctuation, contractions, accents, control characters and overflow.
tok.save_pretrained(out)
parity_texts = [text for text, _ in train + cal] + [
    "I’m making a bad choice.",
    "I DON'T need this app",
    "Café naïve résumé",
    "This—app… can wait!",
    "hello\x00world \t test",
    "[CLS] bad [SEP]",
    "中文 this app",
    "👋 hello app",
    "I\u00a0am choosing",
    "hello " * 127,
]
parity_input = Path(workspace.name) / "tokenizer-input.json"
parity_output = Path(workspace.name) / "tokenizer-output.json"
parity_input.write_text(json.dumps(parity_texts))
subprocess.run(
    [
        str(evaluator),
        "--tokenize",
        str(out / "vocab.txt"),
        str(parity_input),
        str(parity_output),
    ],
    check=True,
)
for text, actual in zip(parity_texts, json.loads(parity_output.read_text())):
    normalized = normalized_input(text)
    valid = (
        2 <= len(normalized.split()) <= 80
        and len(normalized.encode("utf-16-le")) // 2 <= 400
        and any(c.isalpha() for c in normalized)
        and not any(
            marker in normalized
            for marker in ["[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]"]
        )
    )
    expected = (
        tok(normalized, padding="max_length", max_length=128, truncation=False)[
            "input_ids"
        ]
        if valid
        else None
    )
    if expected is not None and len(expected) > 128:
        expected = None
    if actual != expected:
        raise RuntimeError(f"Swift/training tokenizer mismatch: {text!r}")
print(f"Swift tokenizer parity passed for {len(parity_texts)} cases.", flush=True)


device = "mps" if torch.backends.mps.is_available() else "cpu"
model.to(device)
loader = DataLoader(
    encode(train),
    batch_size=32,
    shuffle=True,
    generator=torch.Generator().manual_seed(8241),
)
caldata = encode(cal)
optim = torch.optim.AdamW(model.parameters(), lr=5e-5, weight_decay=0.01)
weights = torch.tensor(
    [1.0, len([y for s, y in train if y == 0]) / sum(y for s, y in train)],
    device=device,
)
lossfn = torch.nn.CrossEntropyLoss(weight=weights, label_smoothing=0.03)
scheduler = torch.optim.lr_scheduler.LinearLR(
    optim, start_factor=1.0, end_factor=0.1, total_iters=8 * len(loader)
)
best = None
chosen = None
out.mkdir(exist_ok=True)
print(
    "device",
    device,
    "parameters",
    sum(p.numel() for p in model.parameters()),
    flush=True,
)
for epoch in range(1, 9):
    model.train()
    total = 0.0
    start = time.monotonic()
    for step, (ids, mask, y) in enumerate(loader):
        optim.zero_grad(set_to_none=True)
        logits = model(input_ids=ids.to(device), attention_mask=mask.to(device)).logits
        loss = lossfn(logits, y.to(device))
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optim.step()
        scheduler.step()
        total += loss.item()
    model.eval()
    scores = []
    with torch.no_grad():
        for ids, mask, y in DataLoader(caldata, batch_size=32):
            scores.extend(
                model(input_ids=ids.to(device), attention_mask=mask.to(device))
                .logits.softmax(-1)[:, 1]
                .cpu()
                .tolist()
            )
    options = []
    for t in [i / 1000 for i in range(500, 1000)]:
        tp = sum(y == 1 and p >= t for (_, y), p in zip(cal, scores))
        fp = sum(y == 0 and p >= t for (_, y), p in zip(cal, scores))
        fn = sum(y for _, y in cal) - tp
        tn = sum(1 - y for _, y in cal) - fp
        pr = tp / (tp + fp) if tp + fp else 0
        rec = tp / sum(y for _, y in cal)
        fpr = fp / sum(1 - y for _, y in cal)
        f1 = (2 * pr * rec / (pr + rec)) if (pr + rec) else 0
        options.append(
            (pr >= 0.95 and rec >= 0.8 and fpr <= 0.03, f1, rec, pr, -float(t), tp, fp)
        )
    selection = max(options)
    print(
        "epoch",
        epoch,
        "loss",
        total / len(loader),
        "seconds",
        time.monotonic() - start,
        "calibration",
        selection,
        flush=True,
    )
    if best is None or selection > best:
        best = selection
        chosen = scores
        model.save_pretrained(out)
        tok.save_pretrained(out)
        (out / "calibration.json").write_text(
            json.dumps(
                {
                    "epoch": epoch,
                    "threshold": -selection[4],
                    "metrics": selection,
                    "scores": scores,
                }
            )
        )
    # Keep the schedule fixed; threshold and epoch are chosen only on calibration.
print("best", best, flush=True)
for (s, y), p in zip(cal, chosen):
    if (p >= -best[4]) != bool(y):
        print("false positive" if y == 0 else "false negative", p, s, flush=True)

if not best[0]:
    raise RuntimeError(
        "No calibration candidate reached precision >=95%, recall >=80%, FPR <=3%. Shipping model untouched."
    )

from pathlib import Path
import json, numpy as np, torch, coremltools as ct
from coremltools.models.neural_network import quantization_utils
from transformers import BertForSequenceClassification

checkpoint = out
model = BertForSequenceClassification.from_pretrained(
    checkpoint, attn_implementation="eager"
).eval()


class Wrapper(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.model = m

    def forward(self, input_ids, attention_mask):
        return self.model(
            input_ids=input_ids, attention_mask=attention_mask
        ).logits.softmax(-1)


traced = torch.jit.trace(
    Wrapper(model),
    (torch.ones((1, 128), dtype=torch.int32), torch.ones((1, 128), dtype=torch.int32)),
)
converted = ct.convert(
    traced,
    convert_to="neuralnetwork",
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
    ],
    outputs=[ct.TensorType(name="probabilities")],
    minimum_deployment_target=ct.target.iOS14,
)
converted = quantization_utils.quantize_weights(converted, nbits=16)
converted.author = "OutLoud contributors; pretrained all-MiniLM-L6-v2 by sentence-transformers"
converted.license = (
    "Apache-2.0 (all-MiniLM-L6-v2 weights and vocabulary); see MODEL_LICENSE.txt"
)
converted.short_description = "Acknowledges that the current choice to use an app is avoidable or counterproductive."
converted.version = "2"
metadata = {
    "policyVersion": "2",
    "trainingSeed": "8241",
    "selectedEpoch": str(
        json.loads((checkpoint / "calibration.json").read_text())["epoch"]
    ),
    "architecture": "minilm-l6-v2-wordpiece-v1",
    "shippingThreshold": str(
        json.loads((checkpoint / "calibration.json").read_text())["threshold"]
    ),
    "vocabularySHA256": hashlib.sha256(
        (checkpoint / "vocab.txt").read_bytes()
    ).hexdigest(),
    "pretrainedModel": "sentence-transformers/all-MiniLM-L6-v2",
    "pretrainedRevision": "1110a243fdf4706b3f48f1d95db1a4f5529b4d41",
}
for split in ["training", "calibration", "test"]:
    data = (root / f"ModelTraining/acknowledgement-{split}.json").read_bytes()
    fingerprint = hashlib.sha256(data).hexdigest()
    if split in training_fingerprints and fingerprint != training_fingerprints[split]:
        raise RuntimeError(
            f"{split} corpus changed during training; refusing to publish"
        )
    metadata[split + "SHA256"] = fingerprint
    metadata[split + "Examples"] = str(sum(len(x) for x in json.loads(data).values()))
converted.user_defined_metadata.update(metadata)
converted.save(str(out / "candidate.mlmodel"))
print("Saved", (out / "candidate.mlmodel").stat().st_size, flush=True)

subprocess.run(
    [
        str(evaluator),
        "--calibration-only" if args.calibration_only else "--promote",
        str(out / "candidate.mlmodel"),
        str(out / "vocab.txt"),
    ],
    check=True,
)
