# Speech error 1107 investigation

Investigated September 9, 2026 against `cd536af` and the September 4 upload
baseline (`19ab2a3`). The report shows an empty transcript, “Getting ready,”
the Instagram phrase, and `kAFAssistantErrorDomain error 1107` with Try again.

The working tree now includes bounded speech-service recovery, fresh recording
objects per attempt, interruption handling and recovery regression tests. This
change has not been uploaded or validated against the reporter's physical
device. See Recovery implemented September 9 below.

## Original finding at `cd536af`

The September 7 code still displays the reported failure when the **active** speech
task receives error 1107. The September 7 refactor protects a new attempt from
callbacks belonging to an old attempt; it does not recover automatically from
an interrupted active speech service. Shipping that refactor alone is not
evidence that this report is resolved.

Apple documents 1107 as “Connection to speech process was interrupted.” It is
distinct from missing speech assets (102), disabled Siri/Dictation (201), an
overlapping recognition request (1100), and authorization failure (1700).
The screenshot alone cannot identify what interrupted the process or whether
the callback belonged to the current attempt.

Source: [Apple's speech-task error reference](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error).

## Release evidence

- Apple's [US lookup endpoint](https://itunes.apple.com/lookup?id=6804832298&country=us),
  queried September 9, returned store version `1.0`, initial release
  `2026-09-05T07:00:00Z`, and current-version release
  `2026-09-06T05:40:25Z`. It does not expose the uploaded build number.
- `AppStore/READY_TO_SUBMIT.md` records uploading binary `1.0.0 (4)` September 4.
  Two local September 4 archives also report `1.0.0 (4)`; there are no later
  OutLoud archives in the local Xcode Archives directory.
- Speech code was unchanged between August 24 (`bc464f1`) and September 7
  (`cd536af`). The September 4 fixes concerned Screen Time and reminders.
- Therefore the public release predates the September 7 speech changes. Build 4
  is the likely shipping binary, but its exact selection has not been verified
  in App Store Connect or on the reporter's phone. The public store version and
  archived binary version differ; do not use `1.0` alone as a build identifier.
- The checkout still declares `1.0.0 (4)`. Its version number does not prove that
  its current source has been uploaded. A future upload needs a fresh build
  number and the appropriate new App Store version.

## Code trace

In the upload baseline, `recognitionTask` forwards `error.localizedDescription`
into the exact displayed error whenever `isListening` is true. `stop()` then
sets `isListening` to false. `ChallengeView.completionTitle` consequently says
“Getting ready,” even though recognition has failed. That heading is not
evidence of a permission/startup hang. No visible transcript means no retained
nonempty recognition result at the time of the screenshot, not proof that the
microphone never started.

In the September 7 source, before this recovery change:

1. `SystemSpeechCapture.start` receives Apple's error and emits
   `.failure(error.localizedDescription)`.
2. `SpeechChallengeController.receive` handles it during listening or
   finalization, calls `fail`, stops capture, and sets the same error string.
3. `ChallengeView` shows the same heading, error, and Try again button.
4. Try again starts a new capture. Success still depends on Apple's service
   working on that attempt. There is no special handling for 1107, automatic
   reconnect, or structured error classification.

The old controller did not associate callbacks with an attempt. A callback
from cancelled attempt A could arrive after attempt B set `isListening = true`
and stop B. The current `sessionID` guard prevents that sequence. It also
prevents a cancelled permission prompt from starting hidden capture, waits for
final recognition before accepting a phrase, and bounds finalization with a
timeout. These are real improvements, but the report does not establish that
an old callback caused this particular incident.

## Original deterministic reproduction

The initial investigation added three tests that reproduced the existing
behavior. They have now been replaced with recovery regression tests:

- `testActiveSpeechServiceInterruptionReproducesReportedErrorAndCanRetry`
  injects `NSError(domain: "kAFAssistantErrorDomain", code: 1107)` through the
  same localized-string event used by the system capture. It checks the empty
  transcript, stopped recording, exact error, and no unlock. It then retries,
  injects stale failure/success callbacks from the previous attempt, and checks
  that only a new final result unlocks.
- `testSpeechServiceInterruptionWhileFinalizingNeverUnlocksPartialMatch`
  injects the interruption after a matching partial transcript and Done
  speaking. It checks that neither the partial match nor a late final callback
  unlocks after failure.
- `testSpeechServiceInterruptionReproducesScreenshotAndRetryRecovers` uses the
  production SwiftUI screen with simulator-only scripted speech. It checks the
  reported phrase, Getting ready, error 1107, and Try again, saves a screenshot
  attachment, then checks successful retry. The fixture is excluded from
  Release and physical-device builds.

Run the current speech/UI recovery coverage with:

```sh
xcodebuild -project OutLoud.xcodeproj -scheme OutLoud \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:OutLoudTests/SpeechFlowTests \
  -only-testing:OutLoudUITests/CoreFlowUITests \
  CODE_SIGNING_ALLOWED=NO test
```

These tests inject the reported callback; they do not reproduce an actual
Apple speech-process interruption or prove a device will recover on retry.

Validation on September 9: **15 tests passed, zero failures** (9 speech flow
tests and 6 UI tests), on iPhone 17 Simulator / iOS 26.5 with Xcode 26.6.
The screenshot reproduction and retry test passed. Local result bundle:
`/tmp/OutLoud-Speech1107-20260909.xcresult`. The screenshot is retained as the
“Reproduced speech error 1107” attachment. `git diff --check` also passed.

## Remaining device investigation

The reporter's iPhone model, iOS version, installed build, first-attempt versus
retry history, and whether Try again succeeded are still needed. No physical
microphone/service-interruption reproduction has been performed in this
investigation.

On a test iPhone, compare the shipping build and a separately identified build
containing this recovery change, recording the installed version/build and iOS
version each time:

1. Start a fresh practice pause in Specific phrases mode with the reported
   Instagram phrase. Test first use after allowing microphone/speech access,
   then normal subsequent attempts.
2. Cancel/reopen rapidly and retry after an error. Capture timestamps to
   distinguish a previous task's callback from the active task.
3. Test background/foreground, locking/unlocking, a phone-call interruption,
   and a headset disconnect during listening, then during finalization. These
   are candidate interruption triggers, not known ways to force error 1107.
4. After an error, test Try again and a fresh launch. Verify recording stops,
   the user can recover, and incomplete speech never unlocks an app.

5. Under Settings > Developer, use Reset Media Services during listening and
   during recovery. Verify the microphone stays stopped until the person taps
   Try again. This exercises audio-service reset handling; it is not a promise
   that Apple will emit speech error 1107.

Use Console.app with the OutLoud subsystem and relevant Apple speech/audio
process logs. This change restores speech attempt IDs, lifecycle phase and
error domain/code in local unified logs, without audio, transcripts or error
userInfo. The original screenshot still cannot establish the device trigger.

## Recovery implemented September 9

- Preserve the actual error across the speech-capture boundary. Classify
  `kAFAssistantErrorDomain` 1107 (interrupted) and 1101 (invalidated) by domain
  and code, never by localized text.
- On the first service failure in a user-initiated attempt, invalidate all old
  callbacks, stop capture, discard partial speech, wait 600 milliseconds, then
  create a new audio engine, recognizer and recognition request. The app must
  be active both when recovery is scheduled and when it starts.
- Show Reconnecting and ask the person to repeat the full phrase. Keep that
  instruction visible when listening resumes. Only a new final matching
  transcript can unlock; partial or late results cannot.
- Allow one automatic reconnect per user-initiated attempt. A second failure
  stops capture and shows a readable retry message under Couldn’t listen.
  Manual retry creates fresh objects and resets the one-reconnect allowance.
- Cancel pending recovery when the user cancels, starts another attempt, or
  backgrounds the app. Audio-session interruption and media-service loss/reset
  notifications stop capture and require user-initiated retry, including when
  they arrive during the reconnect delay.
- Preserve the existing requirement for on-device recognition. No server
  fallback, transcription upload or automatic unlock has been added.

Apple recommends recreating audio objects following a media-service reset and
waiting for user action before restarting recording:
[media-service reset documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification).
The bounded 600-millisecond retry for speech-service errors is an application
recovery policy, not an Apple guarantee that its service will be ready.

Regression coverage includes successful reconnect, repeated failure and manual
retry, finalization interruption, stale callbacks, cancellation, replacement
attempts, inactive/background transitions, startup invalidation, and audio
notifications. Simulator UI tests cover automatic recovery and the exhausted
recovery state followed by manual retry. Real-device validation remains NOT RUN.

Validation completed September 9 on Xcode 26.6:

- Full simulator suite: 89 tests executed, one existing model-inference test
  skipped because the simulator lacks Apple's language asset, zero failures.
- After the final actor-isolation adjustment and four additional lifecycle
  regressions: all 24 speech/UI tests passed (17 speech, 7 UI), zero failures.
- Unsigned Release build for generic iOS device: BUILD SUCCEEDED. This checks
  the production compilation path, not microphone behavior on an iPhone.
- `git diff --check`: passed.

Local artifacts: `/tmp/OutLoud-Speech1107-Recovery-Final-20260909.xcresult`
and `/tmp/OutLoud-Speech1107-DeviceBuild.log`. The final UI result retains the
“Speech interruption recovery exhausted” screenshot attachment.
