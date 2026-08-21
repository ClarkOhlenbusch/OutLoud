# Contributing

Thank you for helping improve OutLoud.

## Before opening a pull request

1. Keep changes focused and preserve the minimal user experience.
2. Never log spoken phrases, transcripts, Screen Time tokens, or app identities.
3. Add or update tests for deterministic behavior.
4. Build the full scheme with code signing disabled:

   ```sh
   xcodebuild -project OutLoud.xcodeproj -scheme OutLoud -sdk iphoneos \
     -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
   ```

5. Test Screen Time, shield, App Group, Shortcut, and speech changes on a physical iPhone.

## Reporting issues

Include the iOS and Xcode versions, the stage of the flow that failed, and relevant unified logs from the `com.clarkohlenbusch.outloud` subsystem. Remove personal information before posting logs publicly.
