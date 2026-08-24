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

After a successful pause, OutLoud unlocks the app temporarily and can send you straight back to it.

## A small model with one careful job

Flexible mode is not a chatbot. It is a compact binary classifier trained to answer one question: **did this person acknowledge that opening the app is avoidable or counterproductive?**

OutLoud uses three layers instead of asking a model to decide everything:

| Layer | What it handles |
| --- | --- |
| Deterministic matching | An exact saved phrase, including harmless speech-recognition differences. |
| Safety policy | Clear acknowledgments are accepted; questions, quoted speech, opposite intent, and necessary-use statements are rejected. |
| Core ML classifier | Nuanced wording that is relevant but not obvious enough for a rule. |

That final layer is a Create ML text classifier built with transfer learning from Apple's revision-1 BERT contextual embedding. The classifier bundled with OutLoud is only **1.3 MB**; Apple supplies the larger language embedding through iOS, and inference stays on-device.

### Current model

| Training corpus | Held-out corpus | Threshold | Precision | Recall | False-positive rate |
| :---: | :---: | :---: | :---: | :---: | :---: |
| 392 | 80 | 0.88 | 88.2% | 50.0% | 4.0% |

These are raw classifier results on the separate held-out set. The runtime safety policy is applied before inference and rejects known false-positive patterns on top of that.

The bias toward precision is intentional: asking someone to try again is less harmful than silently removing the pause. During training, the script searches confidence thresholds and refuses to replace the shipping model unless one reaches at least 85% precision, 20% recall, and a 5% or lower false-positive rate.

The original training sentences, held-out evaluation set, generated model, and complete training script are all versioned in this repository. Retraining is one command:

```sh
xcrun swift ModelTraining/train-acknowledgement-classifier.swift
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
5. Continue with a temporary access window, then pause again on the next visit or when the timer ends.

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
