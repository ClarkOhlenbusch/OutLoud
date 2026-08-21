# App Store submission checklist

## 1. Apple-managed prerequisite

The Account Holder must request **Family Controls (Distribution)** for the main app and each of its three Screen Time extension App IDs:

- `com.clarkohlenbusch.outloud`
- `com.clarkohlenbusch.outloud.shield-configuration`
- `com.clarkohlenbusch.outloud.shield-action`
- `com.clarkohlenbusch.outloud.device-activity-monitor`

In the Apple Developer portal, open **Certificates, Identifiers & Profiles > Capability Requests**, request Family Controls for each identifier, and wait until each request shows **Assigned** with App Store distribution support.

## 2. Create the App Store Connect record

The Account Holder, Admin, or App Manager creates a new iOS app with the values in [metadata.md](metadata.md). The latest agreement in App Store Connect's Business section must be accepted first.

Use the unique extended store name if available. Do not change the bundle ID after uploading a build.

## 3. Complete product information

- Confirm name, subtitle, description, keywords, categories, copyright, and URLs.
- Under App Privacy, select **No, we do not collect data from this app** and publish the response.
- Complete the age-rating questionnaire.
- Set availability and price to Free.
- Answer export compliance: the app only uses encryption supplied by Apple's operating system and does not implement proprietary encryption.

## 4. Capture screenshots

The first release targets iPhone only. Capture one to ten portrait screenshots on the iPhone 17 Pro Max. Use clean device state and avoid exposing private notifications or unrelated app content.

Suggested sequence:

1. Minimal protection status screen
2. Choose-apps onboarding step
3. Choose-phrase onboarding step
4. Reactive voice orb
5. Successful green confirmation

## 5. Archive and upload

After all four Family Controls distribution requests are assigned:

1. In Xcode, select **Any iOS Device (arm64)**.
2. Choose **Product > Archive**.
3. In Organizer, select the archive and choose **Distribute App > App Store Connect > Upload**.
4. Keep automatic signing enabled and let Xcode refresh the distribution profiles.
5. Wait for App Store Connect to finish processing the build.

## 6. TestFlight before review

Add the processed build to internal TestFlight testing. Verify onboarding, direct shield handoff, speech permission denial/recovery, automatic re-arm, device restart behavior, and protection removal.

## 7. Submit for review

Select the processed build on the 1.0.0 version page, complete the review contact fields, paste the review notes from [metadata.md](metadata.md), and submit.

Do not submit until Family Controls distribution is assigned to all four identifiers; development entitlement approval alone is not sufficient.
