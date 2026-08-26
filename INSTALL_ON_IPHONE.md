# Install OutLoud on an iPhone

## Requirements

- A Mac with Xcode 26 or newer
- An iPhone running iOS 17 or newer
- An active Apple Developer Program team
- A cable for initial device pairing

## Install

1. Open `OutLoud.xcodeproj` in Xcode.
2. Connect and unlock the iPhone, tap **Trust** if prompted, and enable **Developer Mode** under **Settings > Privacy & Security**.
3. Select the blue OutLoud project in Xcode.
4. For `OutLoud`, `OutLoudShieldConfiguration`, `OutLoudShieldAction`, `OutLoudDeviceActivityMonitor`, and `OutLoudTests`, select the same team under **Signing & Capabilities**.
5. Confirm that the app and three extensions have **Family Controls** and the `group.com.clarkohlenbusch.outloud` App Group.
6. Select the connected iPhone as the run destination and press **Run** (`Command-R`).

## First launch

OutLoud guides the user through one item per screen:

1. Approve Screen Time access.
2. Choose protected apps individually and match their automatic return destinations.
3. Choose one or more spoken phrases, optionally enable flexible acknowledgment matching, and practice.
4. Choose whether OutLoud asks again after a timer or every visit. The every-visit option includes one-time Shortcuts automation instructions.
5. Choose whether to receive always-on usage reminders every 1, 5, or 10 minutes.
6. Turn on protection, or finish with reminders only.

Microphone and Speech Recognition access are requested during the practice. On iOS versions before 26.5, notification access is also needed because a notification is used as the fallback bridge from the shield to OutLoud. On any supported iOS version, choosing a usage-reminder interval requests notification access. Those reminders stay active for each selected app whether protection is on or off, until you turn them off in Usage reminders.

## Test the complete flow

1. Open a protected app.
2. Tap **Unlock** on the system shield.
3. OutLoud opens to the voice orb on iOS 26.5 or newer.
4. Say the displayed phrase.
5. OutLoud automatically returns to a configured app. If its app link fails, use the visible return button.

## Common fixes

- **Device unavailable:** unlock the iPhone, reconnect it, and wait in **Window > Devices and Simulators**.
- **Signing requires a team:** assign the same team to every app and extension target.
- **Shield never appears:** confirm Screen Time authorization, selected apps, protection status, App Group, and Family Controls capabilities.
- **Speech fails:** enable Microphone and Speech Recognition for OutLoud in iPhone Settings.
- **Old UI or icon remains:** delete OutLoud from the phone, choose **Product > Clean Build Folder**, and run again.

For unified logs and tests, see [DEVELOPMENT.md](DEVELOPMENT.md).
