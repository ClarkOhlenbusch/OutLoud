"""Rebuild deterministic conversational/attribution variants of the seed corpus."""

import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent
corpus = json.loads((root / "acknowledgement-training-seeds.json").read_text())
positive = corpus["acknowledges"][:]
negative = corpus["other"][:]
for sentence in positive:
    for prefix in ["Honestly, ", "I admit it: ", "Right now, "]:
        corpus["acknowledges"].append(prefix + sentence)
    for prefix in [
        "Someone said: ",
        "I disagree with the statement: ",
        "Yesterday I said: ",
        "Is it true that ",
        "The screen says: ",
    ]:
        corpus["other"].append(
            prefix + sentence + ("?" if prefix.startswith("Is") else "")
        )
for sentence in negative:
    for prefix in ["Honestly, ", "To be clear, ", "Well, "]:
        corpus["other"].append(prefix + sentence)
for label in corpus:
    unique = {}
    for sentence in corpus[label]:
        key = " ".join(re.findall(r"\w+", sentence.lower()))
        unique.setdefault(key, sentence)
    corpus[label] = list(unique.values())
(root / "acknowledgement-training.json").write_text(json.dumps(corpus, indent=2) + "\n")
