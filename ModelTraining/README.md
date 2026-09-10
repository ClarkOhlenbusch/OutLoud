# Own words classifier

The positive label, `acknowledges`, means the speaker acknowledges that their
current or imminent choice to use the app is avoidable, distracting, or
counterproductive. The challenge provides context, so “I am making a bad choice”
qualifies without naming an app. A negative opinion about food, weather, app
quality, or another person's behavior does not qualify.

Questions, quotations without endorsement, past-only admissions, denials,
requests to unlock, and statements justifying current use as necessary are
`other`. Being tempted despite admitting distraction is still an acknowledgment;
saying current use is actually required is not. Purpose matters: using an app
to track wasted time is different from admitting to wasting time in the app.

All examples are authored project data, not recorded user speech. Training also
includes controlled sentence variants (conversational filler, quotation,
historical attribution, and denial) and subject/predicate contrast pairs. The
corpus is small and synthetic relative to real speech; these measurements do
not establish population-wide accuracy.

- `acknowledgement-training-seeds.json`: original labeled statements and contrast pairs.
- `acknowledgement-training.json`: fitting data plus deterministic variants,
  reproducible with `python3 ModelTraining/augment-training-data.py`.
- `acknowledgement-calibration.json`: development examples used to select the
  confidence threshold. The previous evaluation corpus is now part of this set
  because it had already been used to tune thresholds and rules. Three candidate
  test sets that failed during development were also retired into calibration;
  the current final test was authored separately afterward.
- `acknowledgement-test.json`: separate final evaluation, used after fitting
  and threshold selection. Do not tune against its errors. If it is used for
  subsequent development, retire it as a test set and collect fresh examples.

The trainer rejects normalized duplicates within or across these files. It
runs the exact `Shared/AcknowledgementDecision.swift`, `AcknowledgementTokenizer.swift`,
and `AcknowledgementInference.swift` used by the app. No keyword can bypass
inference. The exported Core ML model is evaluated with CPU-only configuration.
This checks the portable inference path; it is not an older-iPhone performance
measurement.

Training requires Xcode, Python 3.11, and `uv`. The launcher installs pinned
training dependencies in uv’s environment. Training runs locally; the pretrained
weights are downloaded once from a pinned Google model revision. No corpus is
uploaded. A fixed seed and training schedule are used, but numerical results may
vary between hardware/framework versions. Checkpoint and threshold selection
use calibration only, prioritizing precision among candidates meeting all gates.

Train, evaluate, and replace the bundled assets only after all checks:

```sh
ModelTraining/train-acknowledgement-classifier.sh
```

For development, keep the final test untouched while working on a candidate:

```sh
ModelTraining/train-acknowledgement-classifier.sh --calibration-only /tmp/outloud-candidate
ModelTraining/train-acknowledgement-classifier.sh --promote /tmp/outloud-candidate
```

The second command validates and promotes that exact candidate without another
training run. It verifies corpus hashes and model/policy metadata first. Both
calibration and final test must reach precision >= 95%, recall >= 80%, and a
false-positive rate <= 3%. A failure leaves the bundled model untouched.
Confusion counts and the selected threshold are written beside the model in an
`evaluation.json` report. Model metadata includes corpus hashes and counts,
threshold, policy version, architecture, pretrained revision, and vocabulary hash.

To evaluate the bundled model after adding calibration examples, without fitting,
reselecting its threshold, reading final-test scores, or promoting assets:

```sh
xcrun swiftc -O Shared/PhraseMatcher.swift Shared/AcknowledgementDecision.swift \
  Shared/AcknowledgementTokenizer.swift Shared/AcknowledgementInference.swift \
  ModelTraining/evaluate-acknowledgement-classifier.swift -o /tmp/outloud-evaluate
/tmp/outloud-evaluate --validate-current \
  OutLoud/Models/FlexibleAcknowledgementClassifier.mlmodel \
  OutLoud/Models/AcknowledgementVocabulary.txt
```

This diagnostic command prints JSON with corpus/model fingerprints, confusion
counts, errors, and a `passes` flag. A successful exit means evaluation completed;
check `passes` for the quality gates. It permits changed calibration data and
writes no files. Promotion still requires the candidate's original corpus hashes.

The model is [Google BERT-Medium (8 layers, 512 hidden units)](https://huggingface.co/google/bert_uncased_L-8_H-512_A-8),
fine-tuned end to end and exported as a Core ML neural network with 16-bit
weights. Model and WordPiece vocabulary ship inside the app; classification
requires no downloadable OS embedding or Apple Intelligence. Apache-2.0 license
and attribution are bundled in `OutLoud/Models/MODEL_LICENSE.txt`.

Classification stays on device, using the same CPU backend on older and newer supported
hardware. The app retains its iOS 17 deployment target. Apple's speech recognizer
also requires on-device execution; its speech assets are separate from the
fully bundled classifier. Missing/invalid classifier resources, oversized input,
or inference errors cannot unlock. Run the offline and oldest-device checklist
before release; CPU-only evaluation on a Mac is not an older-iPhone benchmark.

## Bundled model measurement

The selected checkpoint is epoch 6, with threshold 0.994. The model is 82,500,005
bytes (about 83 MB), plus a 231,508-byte vocabulary. The full CPU inference path
reaches 98.0% precision / 85.2% recall on its original 595 calibration examples, and 95.8%
precision / 92.0% recall on the independent 125-example final test. The final
set has 46 true accepts, 2 false accepts, 73 true rejects, and 4 false rejects.
These are synthetic-corpus results, not a guarantee for arbitrary speech.

The calibration corpus subsequently grew to 1,065 examples (465 positive / 600
negative), retaining the original 595 unchanged. At the frozen 0.994 threshold,
the bundled model scores 401 true accepts, 4 false accepts, 596 true rejects,
and 64 false rejects: 99.0% precision, 86.2% recall, and 0.7% false-positive rate.
On the 470 additions alone, it accepts 205 of 235 acknowledgments and rejects
all 235 negatives (100% precision, 87.2% recall). The 30 missed acknowledgments
include slang and indirect admissions. These development results pass the
existing gates; they do not replace independent final-test measurements.
The [expanded validation report](acknowledgement-validation.json) records the
exact model/data hashes and errors. Model weights, threshold, original metadata,
and promotion report remain unchanged; adding calibration data does not train
the model. Future training will use the expanded set for checkpoint/threshold
selection.

[Confusion counts](../OutLoud/Models/FlexibleAcknowledgementClassifier.evaluation.json)
are versioned next to the model. Runtime uses CPU-only execution to match the
evaluator and avoid accelerator rounding around the high score threshold.
A local Mac check measured roughly 15.5 ms median and 16.1 ms p95 warm inference;
these timings do not represent older iPhones. See the device validation checklist
for physical-device latency and offline testing.

Validation on 2026-09-09: all 104 Simulator tests passed (97 unit/flow tests,
including 41 classifier/matcher tests, plus 7 UI tests). The iPhone test target
built and signed, but execution was not run because the connected iPhone was
locked. No older physical iPhone was available for latency/offline validation.
