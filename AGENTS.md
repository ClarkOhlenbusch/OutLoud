# AGENTS.md: Developer & Agent Steering Guide for OutLoud

> **Audience**: This document is the authoritative instruction manual for any autonomous AI coding agent (Antigravity, Cursor, Claude Code, GitHub Copilot, Codex, etc.) and human developers contributing to OutLoud.
> **Scope**: Architecture, versioning protocols, App Store compliance, model calibration, testing gates, and CI/CD pipelines.

---

## 1. Core Mission & Non-Negotiable Architectural Invariants

OutLoud is a mindful app-pause tool for iOS 17+ that intercepts doomscrolling by requiring users to speak an intention or acknowledgment aloud before unlocking protected apps.

1. **Strictly On-Device Privacy (Zero-Network Invariant)**:
   * OutLoud has no user accounts, no analytics SDKs, no tracking, and no external AI/LLM APIs.
   * Speech recognition relies strictly on Apple's on-device speech recognizer (`SFSpeechRecognizer`).
   * Semantic acknowledgment classification runs 100% locally via Core ML on the CPU/Neural Engine.
   * **Never introduce third-party analytics, remote network requests, or server fallbacks.**

2. **Apple Screen Time Architecture**:
   * The project consists of four targets:
     * `OutLoud`: The main SwiftUI application.
     * `OutLoudShieldConfiguration`: Extension supplying custom lock shield UI.
     * `OutLoudShieldAction`: Extension responding to button clicks on system shields.
     * `OutLoudDeviceActivityMonitor`: Extension monitoring foreground app usage and triggering reminders.
   * All targets share App Groups and Family Controls entitlements.

3. **Multi-File Version Synchronization**:
   * Project settings are defined in `project.yml` (XcodeGen) and checked into `OutLoud.xcodeproj/project.pbxproj`.
   * **`MARKETING_VERSION`** and **`CURRENT_PROJECT_VERSION`** must remain identical across `project.yml` and all targets in `project.pbxproj`.

---

## 2. The App Store Release & Version Train Protocol

### The Problem (Apple Error 90062 / 90186)
```text
Error 90062: The value for key CFBundleShortVersionString [X.Y.Z] must contain a higher version than that of the previously approved version [X.Y.Z].
Error 90186: Invalid Pre-Release Train. The train version 'X.Y.Z' is closed for new build submissions.
```
* Once a version train (e.g. `1.0.0`) has been approved on App Store Connect, Apple permanently closes that train.
* Any subsequent build upload with the same `CFBundleShortVersionString` will be immediately rejected during validation.

### Rules for Agents Preparing Releases:
1. **Never reuse an approved or closed version train**:
   * Train `1.0.0` is permanently closed.
   * Next active trains are `1.0.1`, `1.1.0`, etc.
2. **Always use the automated version tool**:
   * Inspect current version:
     ```bash
     ./Scripts/version.sh get
     ```
   * Verify consistency and check against closed trains:
     ```bash
     ./Scripts/version.sh verify
     ```
   * Bump version before creating a release archive:
     ```bash
     ./Scripts/version.sh bump patch   # e.g., 1.0.1 (5) -> 1.0.2 (6)
     ./Scripts/version.sh bump minor   # e.g., 1.0.1 (5) -> 1.1.0 (6)
     ```
   * The script automatically synchronizes `project.yml`, `project.pbxproj`, `AppStore/READY_TO_SUBMIT.md`, and `AppStore/metadata.md`.

---

## 3. Speech & Intent Classification Rules

OutLoud supports two challenge modes: **Specific phrases** and **Own words** (flexible acknowledgments).

### Two-Stage Matching Pipeline:
1. **Stage 1: Explicit Match (`ExplicitAcknowledgementMatcher`)**:
   * Performs exact, deterministic matching against a curated list of complete acknowledgments (e.g., *"this is a bad choice"*, *"I am wasting time"*).
   * Normalizes contractions, whitespace, and terminal punctuation (`.`, `!`).
2. **Stage 2: Semantic Classifier (`FlexibleAcknowledgementMatcher`)**:
   * Evaluates natural paraphrases using the bundled Core ML model: [`sentence-transformers/all-MiniLM-L6-v2`](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (6 layers, 384 hidden units, 22.7M parameters, 43 MB weight footprint).
   * **Active Shipping Threshold**: `0.980` (calibrated via balanced F1-score optimization).

### Intent Safety Guardrails:
* **Interrogative Rejection**: Statements ending with a question mark (`?`, `？`) must **NEVER** unlock the app. Inquiring whether something is a bad choice is not an admission.
* **Contradiction & Excuse Rejection**: Phrases that hedge, negate, or make excuses (e.g., *"maybe I shouldn't be on my phone, but it's not a bad thing"*, *"I need this for work"*, *"Opening this is bad but I don't care"*) must score `< 0.10` and be rejected.
* **Model Quality Gates**: When retraining with `ModelTraining/train-acknowledgement-classifier.sh`:
  * Precision $\ge 95.0\%$
  * Recall $\ge 80.0\%$
  * False Positive Rate $\le 3.0\%$

---

## 4. Testing & Pre-Flight Validation Gates

Before submitting code, opening a PR, or validating an App Store build, agents **MUST** execute the following verification steps:

```bash
# 1. Verify version train & project file consistency
./Scripts/version.sh verify

# 2. Run unit & flow tests on iOS Simulator
xcodebuild test -scheme OutLoud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OutLoudTests

# 3. Run UI automation tests on iOS Simulator
xcodebuild test -scheme OutLoud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OutLoudUITests

# 4. (Optional / Diagnostic) Validate Core ML model calibration
xcrun swiftc -O Shared/PhraseMatcher.swift Shared/AcknowledgementDecision.swift \
  Shared/AcknowledgementTokenizer.swift Shared/AcknowledgementInference.swift \
  ModelTraining/evaluate-acknowledgement-classifier.swift -o /tmp/outloud-evaluate
/tmp/outloud-evaluate --validate-current \
  OutLoud/Models/FlexibleAcknowledgementClassifier.mlmodel \
  OutLoud/Models/AcknowledgementVocabulary.txt
rm -f /tmp/outloud-evaluate
```

---

## 5. CI/CD Workflows (`.github/workflows/`)

| Workflow | Trigger | Description |
| :--- | :--- | :--- |
| **`build.yml`** | Push to `main`, Pull Requests | Runs version verification, compiles all targets, executes `OutLoudTests` and `OutLoudUITests`, and verifies required regressions via `Scripts/verify-regression-results.py`. |
| **`app-store-validate.yml`** | `workflow_dispatch` (manual) or Git Tag (`v*`) | Archives the project for `generic/platform=iOS`, exports an App Store distribution `.ipa`, and runs automated App Store Connect validation (`altool` / TestFlight upload). |

### App Store Connect API Secrets (for GitHub Actions):
* `APP_STORE_CONNECT_API_KEY_ID`: Key ID from App Store Connect (Users and Access > Integrations > App Store Connect API).
* `APP_STORE_CONNECT_ISSUER_ID`: Issuer ID UUID.
* `APP_STORE_CONNECT_API_KEY_BASE64`: Base64-encoded `.p8` private key file.

---

## 6. Quick Reference for Agents

* **Where is version bumped?** Run `./Scripts/version.sh bump patch` (or `minor`).
* **Where is the ML model?** `OutLoud/Models/FlexibleAcknowledgementClassifier.mlmodel`.
* **Where is model inference defined?** `Shared/AcknowledgementInference.swift`.
* **Where is prompt matching handled?** `OutLoud/FlexibleAcknowledgementMatcher.swift`.
* **Where is App Store submission documentation?** `AppStore/READY_TO_SUBMIT.md`.
