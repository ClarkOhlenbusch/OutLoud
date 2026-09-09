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

Logs intentionally omit spoken phrases, recognized transcripts, protected-app tokens, and app identities. Counts and non-sensitive state names are logged publicly so they remain useful when debugging.

The shared Xcode scheme enables `IDEPreferLogStreaming=YES` for Run and Test actions. This addresses Xcode's logging-stream timeout suggestion without changing release behavior.

## Tests

Run the unit, flow and UI suites on an available iPhone Simulator:

```sh
xcodebuild -project OutLoud.xcodeproj -scheme OutLoud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Substitute a Simulator listed by `xcrun simctl list devices available`. The flow
tests use isolated UserDefaults suites and temporary handoff directories, an
in-memory Screen Time adapter and scripted speech callbacks. They do not modify
the real App Group or real managed restrictions. Tests run serially because the
app and extension code share static service adapters.

`OutLoudUITests` uses simulator-only launch fixtures with synthetic tokens and
audio while exercising the production SwiftUI screens. Those fixtures are
excluded from Release and physical-device builds. Follow the
[iPhone validation checklist](docs/DEVICE_VALIDATION.md) for real microphone,
shield handoff, automatic return, foreground-usage counting and re-lock timing.

Select a connected iPhone and choose **Product > Test** (`Command-U`) in Xcode. Results appear in the Test navigator.

The current unit tests cover:

- Phrase collections, normalization, contractions, punctuation, recognition errors, flexible acknowledgments, model loading, safety gates, incomplete phrases, and false positives.
- Every persisted onboarding step, invalid persisted state, back navigation, and progress count.
- Usage-reminder interval persistence, independent monitor generations, notification copy, and event-name parsing.
- Own words versus Specific phrases routing, opposite-intent phrase regressions, reminder cadence changes, and retrying a failed unlock without losing the challenge.
- Partial/final speech sequences, cancellation, stale callbacks, denied permissions, startup errors and finalization timeout.
- Speech-service reconnection, bounded retries, fresh-phrase acceptance, background/cancellation during recovery, and audio interruption/media reset handling. See the [error 1107 investigation](docs/SPEECH_1107_INVESTIGATION.md).
- Independent app access windows, expiry, stale monitor callbacks, practice, cancellation, relaunch and return-mapping persistence.
- The extension's reminder handler through cadence changes, duplicate events, per-app progress, midnight reset and failed-monitor recovery.
- UI onboarding with manual return, mixed mappings, automatic/manual unlock controls and visible unlock retry.

The full app and test bundle can be compiled without signing with:

```sh
xcodebuild -project OutLoud.xcodeproj -scheme OutLoud -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Apple’s Screen Time picker, shields, extension handoff, and speech permissions require a physical device for meaningful end-to-end testing. Those system-owned screens are not good unit-test targets; verify them with the connected-device flow after unit tests pass.

For usage reminders, choose each cadence on a physical iPhone, turn protection off, and keep an individually selected app frontmost through at least two thresholds. Confirm the alert uses the OutLoud icon, names mapped apps, replaces the previous delivered reminder, and pauses that app's elapsed-use count while another app is frontmost. Reopen the first app to confirm its daily count continues rather than restarting. For the 5- and 10-minute cadences, confirm every displayed total is divisible by the selected interval. Then use the subtle turn-off action and confirm reminders stop. Repeat once with Focus enabled to verify the device's Time Sensitive notification setting.

## Flexible-acknowledgment model

Flexible matching uses a Create ML text classifier built on Apple’s revision-1 BERT contextual embedding. Own words mode always applies explicit safety rules to reject questions, quoted statements, unrelated negative language, and opposite intent before model inference. Specific phrases mode uses deterministic matching with normalization, conversational filler, and limited recognition tolerance; character similarity cannot substitute arbitrary words in a multiword phrase.

The original training sentences and a separate held-out evaluation set live in `ModelTraining`. Retrain and replace the bundled model with:

```sh
xcrun swift ModelTraining/train-acknowledgement-classifier.swift
```

The trainer selects a conservative confidence threshold, writes it into the model metadata, and refuses to replace the model unless a held-out threshold reaches at least 85% precision, 20% recall, and a 5% or lower false-positive rate. The production safety gate improves on those raw-model measurements.

Apple distributes the contextual-embedding asset through the operating system. Simulator does not include that downloadable asset, so the model-inference unit test is skipped there; run the full suite on a physical iPhone after the asset is available. Deterministic phrase and safety-gate tests continue to run in Simulator.

## Xcode launch messages

`attach by pid ... failed -- no such process` means the app process ended or restarted before LLDB attached. A one-off instance during reinstall or relaunch is not evidence of an app crash.

`Failed to initialize logging system due to time out` is an Xcode log-stream problem. The scheme workaround is enabled. If it recurs, reconnect the phone and restart Xcode; use Console.app to inspect OutLoud's unified logs independently of Xcode's debug console.
