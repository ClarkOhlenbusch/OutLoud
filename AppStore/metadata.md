# App Store metadata draft

## App record

- Platform: iOS
- Store name: `OutLoud: Mindful App Pause`
- Installed display name: `OutLoud`
- Primary language: English (U.S.)
- Bundle ID: `com.clarkohlenbusch.outloud`
- SKU: `OUTLOUD-IOS-001`
- Version: `1.0.0`
- Price: Free
- Primary category: Productivity
- Secondary category: Health & Fitness
- Copyright: `2026 Clark Ohlenbusch`

The exact store name is a draft until App Store Connect confirms availability. The plain name `OutLoud` is already used by another app.

## Subtitle

`Pause. Speak. Choose.`

## Promotional text

`Put one intentional moment between you and the apps you open on autopilot.`

## Description

OutLoud puts a deliberate pause between you and distracting apps.

Choose the apps you want to protect and set a short intention. When you try to open one, OutLoud asks you to say that intention aloud before continuing. The responsive voice orb gives immediate feedback while you speak, turning a mindless tap into a conscious choice.

FEATURES

- Protect apps using Apple's Screen Time controls
- Choose a phrase that feels personal to you
- Complete the pause with a focused, reactive voice screen
- Practice your phrase during setup
- Re-arm protection after every visit with an optional Shortcuts automation
- Keep settings and challenge state on your device

PRIVATE BY DESIGN

OutLoud has no accounts, advertisements, analytics, or tracking. App selections are represented by private Apple tokens, and OutLoud does not upload your phrase or speech.

OutLoud is a mindfulness tool, not a parental-monitoring service. You remain in control of the apps you select and can turn protection off at any time.

## Keywords

`screen time,mindfulness,focus,digital wellbeing,habits,social media,app blocker,intention`

## URLs

- Marketing: `https://clarkohlenbusch.github.io/OutLoud/`
- Support: `https://clarkohlenbusch.github.io/OutLoud/support/`
- Privacy: `https://clarkohlenbusch.github.io/OutLoud/privacy/`

## App privacy response

Select **No, we do not collect data from this app**. The repository contains no backend, analytics, advertising, or tracking SDK. Apple's system frameworks process Screen Time permission and speech recognition; the developer does not receive that data.

## Age rating draft

Answer **None** for objectionable-content categories unless App Store Connect introduces a category that specifically describes user-configurable text. Expected rating: 4+.

## Review notes

OutLoud uses Apple's Family Controls, Managed Settings, Device Activity, Speech, AVFoundation, and App Intents frameworks.

Test flow:

1. Launch OutLoud and approve individual Screen Time authorization.
2. Select any installed app in Apple's Family Activity picker.
3. Keep or edit the default intention and complete the voice practice.
4. Turn protection on.
5. Open the selected app and tap **Start the pause** on the shield.
6. OutLoud opens to the voice orb. Speak the displayed phrase.
7. After confirmation, return to the selected app using the system app-switch gesture.

No account or review credentials are required. The optional Shortcuts automation is explained during onboarding but is not required to test the core 15-minute access-window behavior.

The Family Controls distribution entitlement must be approved for these identifiers:

- `com.clarkohlenbusch.outloud`
- `com.clarkohlenbusch.outloud.shield-configuration`
- `com.clarkohlenbusch.outloud.shield-action`
- `com.clarkohlenbusch.outloud.device-activity-monitor`
