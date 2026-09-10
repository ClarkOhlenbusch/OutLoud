<p align="center">
  <img src="OutLoud/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="144" alt="OutLoud app icon">
</p>

<h1 align="center">OutLoud</h1>

<p align="center"><strong>Turn autopilot into a choice.</strong></p>
<p align="center">A deliberate pause between you and the apps you open without thinking.</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-0d0a12?style=flat-square&logo=apple&logoColor=white">
  <img alt="Built with SwiftUI" src="https://img.shields.io/badge/SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="On-device processing" src="https://img.shields.io/badge/Processing-On--device-f5c23d?style=flat-square&labelColor=0d0a12">
  <img alt="No tracking" src="https://img.shields.io/badge/Tracking-None-f5c23d?style=flat-square&labelColor=0d0a12">
</p>

---

OutLoud does one thing: it puts a small, intentional decision between you and a distracting app.

## One small pause

| 1. Open | 2. Say it | 3. Choose |
| :---: | :---: | :---: |
| Open a protected app. | Acknowledge the choice out loud. | Continue intentionally—or walk away. |

No feeds. No streaks. No productivity dashboard. Just enough friction to interrupt muscle memory.

## Say it your way

**Own words · Default**<br>
Acknowledge that opening the app is a bad choice. OutLoud understands natural phrasing on-device.

**Specific phrases**<br>
Prefer exact wording? Add your own phrases and require one of them instead.

After a successful pause, OutLoud unlocks the app temporarily. Optional auto-return supports Instagram, TikTok, YouTube, Reddit, and X; other individually selected apps work with manual return.

OutLoud checks the completed recognition result after you pause speaking. In a
noisy environment, tap Done speaking to finish recording. Timed access windows
are tracked separately, so unlocking another app does not shorten the first
app's window.

## A small model with one careful job

Flexible mode is not a chatbot. It is a compact binary classifier trained to answer one question: **did this person acknowledge that opening the app is avoidable or counterproductive?**

Own words accepts complete, explicit acknowledgments such as “this is a bad
choice” directly, including common contractions and terminal periods or
exclamation marks. This matches the whole statement, preserving questions,
quotations, negations, and added clauses. Other wording goes to the classifier.
Words such as “bad,” “this,” or “time” never unlock an app by themselves.
Questions, quotations, denials, unrelated complaints, and necessary-use
statements are included as negative training examples. Saved phrases are used
only in Specific phrases mode.

After three rejected attempts, listening stops with a visible transcript and
retry controls. You can also choose to say a specific phrase for that challenge.

The classifier is a fine-tuned `sentence-transformers/all-MiniLM-L6-v2` model
with its WordPiece vocabulary bundled inside the app (about 43 MB of model weights,
down from 83 MB). Classification runs locally on a background queue using the CPU backend
validated by the trainer. It needs no Apple Intelligence or OS embedding download.
The app still supports iOS 17. For wording that requires the model, an unavailable
model or timed-out check leaves the app locked with a retry message. Complete
explicit acknowledgments do not require model loading. Speech recognition requires on-device
processing and never falls back to a server.

### Current model

| Training | Calibration | Final test | Threshold | Precision | Recall | False-positive rate |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 8,540 | 1,065 | 125 | 0.980 | 96.0% | 96.0% | 2.7% |

These counts describe the bundled model's calibration and independent holdout test.
The full CPU inference path reaches 97.5% precision / 91.4% recall on calibration examples,
and 96.0% precision / 96.0% recall on the independent 125-example final test (48 true accepts,
2 false accepts, 73 true rejects, and 2 false rejects).

Metrics describe the learned model, separately from the explicit-acknowledgment
path. They cover the complete transcript decision through the exported model,
including the same normalization, tokenizer, input limits, and score check used
by the app. The [evaluation report](OutLoud/Models/FlexibleAcknowledgementClassifier.evaluation.json)
records 48 true accepts, 2 false accepts, 73 true rejects, and 2 false rejects on
the final set. Training, threshold calibration, and final testing use separate
corpora. Examples are
synthetic project data; these figures are not a claim of real-world accuracy.

The trainer requires at least 95% precision, 80% recall, and at most a 3%
false-positive rate on calibration and final testing before replacing the model.
The corpora, model, evaluation report, and training script are versioned here:

```sh
ModelTraining/train-acknowledgement-classifier.sh
```

Explore the [`ModelTraining`](ModelTraining/) directory or read the runtime matcher in [`FlexibleAcknowledgementMatcher.swift`](OutLoud/FlexibleAcknowledgementMatcher.swift).

## Private by design

> **No account. No analytics. No advertising. No tracking. No backend.**

Speech and flexible acknowledgment matching stay on the iPhone. App selections are represented by opaque Apple Screen Time tokens; OutLoud does not receive the selected apps' identities.

Read the [privacy policy](docs/privacy.md) or inspect the bundled [privacy manifest](Shared/PrivacyInfo.xcprivacy).

## How it works

1. Choose apps with Apple's Screen Time picker.
2. OutLoud places a system-managed shield over them.
3. Tap the shield to open the focused voice pause.
4. Speak naturally or use a saved phrase.
5. Continue with a temporary access window, or keep always-on reminders running independently at every 1-, 5-, or 10-minute milestone in each selected app’s cumulative foreground time for the day.
6. Pause again on the next visit or when the timer ends.

The friendly onboarding includes the reminder choice and lets people finish with reminders only, without enabling Protection.

## Run on iPhone

You will need Xcode 26 or newer, an iPhone running iOS 17 or newer, and an Apple Developer Program team for the complete Screen Time build.

1. Open `OutLoud.xcodeproj`.
2. Select the same development team for OutLoud, its tests, and all three extensions.
3. Connect and select an unlocked iPhone.
4. Press **Run** (`Command-R`).

See [Install on iPhone](INSTALL_ON_IPHONE.md) for the complete signing and entitlement walkthrough. Screen Time shields require a physical device; Simulator uses sample apps and a simulated phrase match for interface development.

## Built with

- SwiftUI
- Family Controls
- Managed Settings and Managed Settings UI
- Device Activity
- Speech and AVFoundation
- Core ML and Natural Language
- App Intents
- App Group storage shared across three Screen Time extensions

Build the complete app and test bundle without signing:

```sh
xcodebuild -project OutLoud.xcodeproj -scheme OutLoud -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Testing and unified logging are documented in [Development](DEVELOPMENT.md).

## Project status

OutLoud is preparing for its first App Store release. Distribution depends on Apple approving the Family Controls entitlement for the app and each Screen Time extension. Draft metadata and review notes live in [`AppStore`](AppStore/).

## Contributing

Focused issues and pull requests are welcome. Please read [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md) first.

No open-source license has been granted. This repository is public for transparency and collaboration; copyright remains with the author.
