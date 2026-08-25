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
- Save several phrases and say any one that feels natural
- Optionally accept similar acknowledgments using on-device language understanding
- Complete the pause with a focused, reactive voice screen
- Return automatically to individually configured apps after speaking
- Practice your phrases during setup
- Ask again after every visit or after a 15-, 30-, or 60-minute access window
- Keep settings and challenge state on your device

PRIVATE BY DESIGN

OutLoud has no accounts, advertisements, analytics, or tracking. App selections are represented by private Apple tokens, and OutLoud does not upload your phrases or speech. Flexible acknowledgment matching uses Apple's on-device Natural Language framework, with no paid AI service.

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

Under Apple's current questionnaire, answer **Yes/Present** for **Health or Wellness Topics** because OutLoud provides a digital-wellness and self-care experience. Answer **No/None** for parental controls, unrestricted web access, broadly distributed user-generated content, social features, advertising, medical or treatment information, profanity, violence, sexual content, and chance-based activities. Expected rating: 9+.

## Review notes

OutLoud uses Apple's Family Controls, Managed Settings, Device Activity, Speech, AVFoundation, and App Intents frameworks.

Test flow:

1. Launch OutLoud and approve individual Screen Time authorization.
2. Select an installed app individually in Apple's Family Activity picker and match it to a supported automatic return destination.
3. Keep or edit the default intention and complete the voice practice.
4. Turn protection on.
5. Open the selected app and tap **Unlock** on the shield.
6. OutLoud opens to the voice orb. Speak the displayed phrase.
7. After confirmation, OutLoud attempts to reopen the mapped destination automatically and provides a return button if the app link fails.

No account or review credentials are required. Onboarding offers a timer-based access window that needs no automation, or an every-visit option with Shortcuts setup instructions.

The Family Controls distribution entitlement must be approved for these identifiers:

- `com.clarkohlenbusch.outloud`
- `com.clarkohlenbusch.outloud.shield-configuration`
- `com.clarkohlenbusch.outloud.shield-action`
- `com.clarkohlenbusch.outloud.device-activity-monitor`
