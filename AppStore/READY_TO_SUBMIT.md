# OutLoud App Store Connect submission packet

Prepared September 4, 2026.

## Current release status

- App Store Connect app: [OutLoud: Mindful App Pause](https://appstoreconnect.apple.com/apps/6804832298/distribution/ios/version/inflight)
- Apple app ID: `6804832298`
- Bundle ID: `com.clarkohlenbusch.outloud`
- Previously uploaded build: `1.0.0 (3)` (rejected under Guideline 2.1(a))
- Next build to upload: `1.0.0 (4)`; this fixes Screen Time authorization on current iPadOS and makes usage reminders follow cumulative daily app time
- Build status: not yet uploaded
- Distribution entitlements: approved for the app and all three extensions
- Screenshots: four App Store-valid 6.5-inch JPEGs in [Screenshots-6.5](Screenshots-6.5)

## 1. Match the App Store version to the binary

On **Distribution > iOS App > 1.0 Prepare for Submission**, change the **Version** field from `1.0` to:

```text
1.0.0
```

Click **Save** before selecting the build. The uploaded binary's `CFBundleShortVersionString` is `1.0.0`, and Apple says the App Store Connect version should match it.

## 2. Complete App Information

Open **General > App Information** and enter or confirm:

| Field | Value |
| --- | --- |
| Name | `OutLoud: Mindful App Pause` |
| Subtitle | `Pause. Speak. Choose.` |
| Primary language | English (U.S.) |
| Primary category | Productivity |
| Secondary category | Health & Fitness |
| Content rights | No, the app does not contain, show, or distribute third-party content |
| Made for Kids | No |

For **Age Rating**, use these answers:

- Parental controls: No. OutLoud is a self-directed mindfulness tool, not a parent/guardian monitoring tool.
- Age assurance: No.
- Unrestricted web access: No. The app has no embedded browser.
- User-generated content: No. User phrases stay local and are not distributed to anyone.
- Social media: No.
- Messaging and chat: No.
- Advertising: No.
- Profanity or crude humor: None.
- Horror or fear themes: None.
- Alcohol, tobacco, or drug references: None.
- Medical or treatment information: None.
- Health or wellness topics: Yes/Present. OutLoud gives a digital-wellness and self-care experience.
- Sexual or suggestive content: None.
- Violence and weapons: None.
- Gambling, simulated gambling, contests, and loot boxes: None.

The expected result under Apple's current rating system is **9+**. Save the questionnaire.

## 3. Complete App Privacy

Open **General > App Privacy**.

1. Add this privacy policy URL:

   ```text
   https://clarkohlenbusch.github.io/OutLoud/privacy/
   ```

2. For data collection, select **No, we do not collect data from this app**.
3. Click **Save**, then **Publish**, and confirm **Publish**.

The app has no backend, accounts, analytics, advertising, or tracking SDK. Phrases, app-selection tokens, and challenge state stay on device. Speech recognition explicitly requires Apple's on-device recognition.

## 4. Set pricing and availability

Open **Monetization > Pricing and Availability**.

- Price: **Free**
- Distribution: **Public**
- Countries or regions: choose all countries or regions unless you personally want a narrower launch
- Mac with Apple silicon: do not enable for this release; the iPhone app has not been tested there
- Apple Vision Pro: do not enable for this release; the iPhone app has not been tested there

If Apple asks for EU Digital Services Act trader status, answer based on your actual legal/business status. Do not guess—this is an account-holder legal declaration.

## 5. Upload screenshots and version metadata

Return to **Distribution > iOS App > 1.0.0 Prepare for Submission**.

### Screenshots

In the visible **iPhone 6.5-inch Display** slot, upload these files in this order:

1. [01-welcome.jpg](Screenshots-6.5/01-welcome.jpg)
2. [02-choose-apps.jpg](Screenshots-6.5/02-choose-apps.jpg)
3. [03-choose-response.jpg](Screenshots-6.5/03-choose-response.jpg)
4. [04-ask-again.jpg](Screenshots-6.5/04-ask-again.jpg)

Each file is `1284 × 2778`, JPEG, and has no alpha channel. They match the dimensions requested by the visible 6.5-inch slot.

### Promotional text

```text
Put one intentional moment between you and the apps you open on autopilot.
```

### Description

```text
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
- Keep strong reminders running at every 1-, 5-, or 10-minute milestone in each selected app's daily total, even with protection off
- Keep settings and challenge state on your device

PRIVATE BY DESIGN

OutLoud has no accounts, advertisements, analytics, or tracking. App selections are represented by private Apple tokens, and OutLoud does not upload your phrases or speech. Flexible acknowledgment matching uses Apple's on-device Natural Language framework, with no paid AI service.

OutLoud is a mindfulness tool, not a parental-monitoring service. You remain in control of the apps you select and can turn protection off at any time.
```

### Keywords

```text
screen time,mindfulness,focus,digital wellbeing,habits,social media,app blocker,intention
```

### URLs and remaining fields

| Field | Value |
| --- | --- |
| Support URL | `https://clarkohlenbusch.github.io/OutLoud/support/` |
| Marketing URL | `https://clarkohlenbusch.github.io/OutLoud/` |
| Version | `1.0.0` |
| Copyright | `2026 Clark Ohlenbusch` |
| Routing App Coverage File | Leave empty |

## 6. Upload and select the updated build

Archive and upload `1.0.0 (4)` using the steps in [SUBMISSION.md](SUBMISSION.md). After App Store Connect finishes processing it, click **Add Build**, select `1.0.0 (4)`, and click **Done**. Do not select `1.0.0 (3)` because it predates the current iPadOS authorization fix and cumulative daily reminder thresholds.

If App Store Connect asks about encryption, the app does not implement proprietary or standard encryption algorithms. It only invokes ordinary system-handled URLs when returning to supported apps. Choose the answer equivalent to **None of the algorithms mentioned above / only encryption within Apple's operating system**, which requires no export documentation.

Click **Save**.

## 7. Enter App Review information

Leave **Sign-in required** turned off. There is no account or login.

| Field | Value |
| --- | --- |
| First name | `Clark` |
| Last name | `Ohlenbusch` |
| Phone number | **Enter your current phone number** |
| Email | `clark.ohlenbusch@gmail.com` |
| Attachment | Leave empty |

Paste these review notes:

```text
OutLoud is a self-directed mindfulness app that uses Apple's Family Controls, Managed Settings, Device Activity, Speech, AVFoundation, and App Intents frameworks. No account or review credentials are required.

Suggested review flow:
1. Launch OutLoud and approve individual Screen Time authorization.
2. In Apple's Family Activity picker, select an installed app individually.
3. Keep or edit the default intention, complete voice practice, and choose a timer-based access window.
4. Choose a 1-, 5-, or 10-minute usage reminder, or select Not now.
5. Turn protection on. When reminders are enabled, onboarding also offers a reminders-only completion path.
6. Open the selected app and tap Unlock on the system shield.
7. OutLoud opens to the voice orb. Speak the displayed phrase.
8. After confirmation, OutLoud removes the shield for the selected access window and provides a return button.
9. Usage reminders use local notifications at the user-selected interval, based on each app’s cumulative foreground time for the current day. For example, a 5-minute interval notifies at 5, 10, 15, and subsequent daily totals divisible by 5. The total continues across visits, resets at midnight, and reminders work independently when protection is off. Notification access is requested only when an interval is chosen (or when an older iOS release needs the shield handoff fallback).

The timer-based access-window option needs no Shortcuts automation. The every-visit option includes separate Shortcuts setup instructions.

OutLoud has no backend, accounts, analytics, advertising, or tracking. App selections use private Apple tokens. User phrases, speech, and challenge state are not uploaded. Speech recognition explicitly requires on-device recognition.

Family Controls distribution approval is assigned to the main app and all three Screen Time extensions.
```

Under **App Store Version Release**, select **Automatically release this version** unless you specifically want to hold the approved release for a manual launch.

Click **Save**.

Reply to the Guideline 2.1(a) message after selecting build `1.0.0 (4)`:

```text
Hello App Review,

Thank you for the report. We addressed the Screen Time authorization issue in build 1.0.0 (4).

The authorization flow now recognizes every successful authorization state available on current iPadOS, prevents overlapping requests, and automatically retries a transient Family Controls network/setup failure once. If the device cannot authorize Screen Time because of its account, passcode, restrictions, or another controlling app, OutLoud now shows a specific recovery step instead of the underlying system error.

We also verified that the app and all three embedded Screen Time extensions contain the Family Controls entitlement, and ran the test suite in iPhone compatibility mode on iPadOS 26.5.

Please review build 1.0.0 (4). If Screen Time authorization still fails in your environment, please send the exact error text or a screenshot so we can identify the system error case.

Thank you.
```

## 8. Optional sections to skip for version 1.0.0

- App previews
- Routing coverage file
- App Clip
- iMessage App
- In-app purchases and subscriptions
- Game Center
- App Review attachment
- Accessibility Nutrition Labels, until the app has been audited against Apple's complete-task criteria

## 9. Submit

1. On the version page, click **Add for Review**.
2. Create a new submission if prompted and add version `1.0.0`.
3. Resolve any red validation messages by returning to the named section.
4. Click **Submit to App Review** and confirm.

If Apple shows a validation message that is not covered above, copy its exact text before changing anything.
