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

Flexible matching uses a bundled Core ML classifier with Apple's contextual language embedding. The training data, held-out evaluation set, and reproducible trainer are included in [`ModelTraining`](ModelTraining/).

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
