# OutLoud development

## Logging

OutLoud uses Apple's unified logging system under this subsystem:

```text
com.clarkohlenbusch.outloud
```

The categories are `Lifecycle`, `Onboarding`, `ScreenTime`, `Challenge`, `Speech`, and `Shortcuts`.

To see logs from the app and all three Screen Time extensions:

1. Connect the iPhone to the Mac.
2. Open **Console.app** and select the iPhone in the sidebar.
3. Search for `subsystem:com.clarkohlenbusch.outloud`.
4. Reproduce the issue.

Logs intentionally omit the spoken phrase, recognized transcript, protected-app tokens, and app identities. Counts and non-sensitive state names are logged publicly so they remain useful when debugging.

The shared Xcode scheme enables `IDEPreferLogStreaming=YES` for Run and Test actions. This addresses Xcode's logging-stream timeout suggestion without changing release behavior.

## Tests

Select a connected iPhone and choose **Product > Test** (`Command-U`) in Xcode. Results appear in the Test navigator.

The current unit tests cover:

- Phrase normalization, contractions, punctuation, recognition errors, incomplete phrases, and false positives.
- Every persisted onboarding step, invalid persisted state, back navigation, and progress count.

The full app and test bundle can be compiled without signing with:

```sh
xcodebuild -project OutLoud.xcodeproj -scheme OutLoud -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Apple's Screen Time picker, shields, extension handoff, and speech permissions require a physical device for meaningful end-to-end testing. Those system-owned screens are not good unit-test targets; verify them with the connected-device flow after unit tests pass.

## Xcode launch messages

`attach by pid ... failed -- no such process` means the app process ended or restarted before LLDB attached. A one-off instance during reinstall or relaunch is not evidence of an app crash.

`Failed to initialize logging system due to time out` is an Xcode log-stream problem. The scheme workaround is enabled. If it recurs, reconnect the phone and restart Xcode; use Console.app to inspect OutLoud's unified logs independently of Xcode's debug console.
