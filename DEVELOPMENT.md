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

- Phrase collections, normalization, contractions, punctuation, recognition errors, model loading, input/score validation, incomplete phrases, and semantic false positives using the bundled model.
- Every persisted onboarding step, invalid persisted state, back navigation, and progress count.
- Usage-reminder interval persistence, independent monitor generations, notification copy, and event-name parsing.
- Own words versus Specific phrases routing, opposite-intent phrase regressions, reminder cadence changes, and retrying a failed unlock without losing the challenge.
- Partial/final speech sequences, cancellation, stale callbacks, denied permissions, startup errors and finalization timeout.
- Automatic listening after rejected phrases in both modes, repeated mismatches, and cancellation/background during classification. A mismatch shows guidance without a retry button; actual recording failures retain Restart listening.
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

Own words uses a fine-tuned BERT-Medium model and WordPiece vocabulary, both
bundled with the app. Every accepted transcript requires a model score; there are no
keyword-based passes or substring vetoes. The app and trainer share input limits
and score validation in `Shared/AcknowledgementDecision.swift`. Specific phrases
still uses deterministic normalization and limited recognition tolerance.

Training, calibration, and final-test corpora are separate. See
[ModelTraining/README.md](ModelTraining/README.md) for labeling rules, synthetic
data limitations, calibration-only development, and exact-candidate promotion.
Train and replace the bundled model with:

```sh
ModelTraining/train-acknowledgement-classifier.sh
```

The trainer chooses the threshold using calibration data, checks the exported
Core ML path on CPU, then evaluates the untouched final test.
Both must reach 95% precision, 80% recall, and at most 3% false positives before
an atomic model replacement. Model metadata binds the threshold to the decision
policy and corpus hashes; the adjacent evaluation report records confusion counts.

Classification needs no OS embedding download or Apple Intelligence. Speech
recognition also requires local processing, with no server fallback. Inference
and model loading are serialized off the main thread; a 15-second timeout or
unavailable model leaves protection intact. The iOS 17 deployment target is
unchanged. Complete the oldest-device and Airplane Mode checks in
[the device checklist](docs/DEVICE_VALIDATION.md) before release.

Semantic integration tests now run in Simulator as well as on iPhone because
all classification resources are bundled. Speech flow tests inject inference
to control cancellation, failure, and latency. Simulator UI fixtures use a
classifier stub only for UI test launches; this is excluded from physical-device
and Release builds and is not evidence of model accuracy.

## Xcode launch messages

`attach by pid ... failed -- no such process` means the app process ended or restarted before LLDB attached. A one-off instance during reinstall or relaunch is not evidence of an app crash.

`Failed to initialize logging system due to time out` is an Xcode log-stream problem. The scheme workaround is enabled. If it recurs, reconnect the phone and restart Xcode; use Console.app to inspect OutLoud's unified logs independently of Xcode's debug console.
