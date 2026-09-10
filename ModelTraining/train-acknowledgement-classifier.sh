#!/bin/sh
set -eu
training_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec uv run --python 3.11 --script "$training_dir/train-acknowledgement-classifier.py" "$@"
