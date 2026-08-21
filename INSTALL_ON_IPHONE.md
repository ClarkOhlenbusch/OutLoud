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
2. Choose protected apps.
3. Choose and practice the spoken phrase.
4. Optionally configure the one-time Shortcuts automation for automatic re-arming.
5. Turn on protection.

Microphone and Speech Recognition access are requested during the practice. On iOS versions before 26.5, notification access is also needed because a notification is used as the fallback bridge from the shield to OutLoud.

## Test the complete flow

1. Open a protected app.
2. Tap **Start the pause** on the system shield.
3. OutLoud opens to the voice orb on iOS 26.5 or newer.
4. Say the displayed phrase.
5. After the green confirmation, use the bottom-edge app-switch gesture to return to the protected app.

## Common fixes

- **Device unavailable:** unlock the iPhone, reconnect it, and wait in **Window > Devices and Simulators**.
- **Signing requires a team:** assign the same team to every app and extension target.
- **Shield never appears:** confirm Screen Time authorization, selected apps, protection status, App Group, and Family Controls capabilities.
- **Speech fails:** enable Microphone and Speech Recognition for OutLoud in iPhone Settings.
- **Old UI or icon remains:** delete OutLoud from the phone, choose **Product > Clean Build Folder**, and run again.

For unified logs and tests, see [DEVELOPMENT.md](DEVELOPMENT.md).
