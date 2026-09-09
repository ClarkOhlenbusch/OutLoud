# Core-flow validation on iPhone

Run this before a release and after changes to speech, shielding or reminders.
Simulator UI fixtures replace audio and Screen Time; passing them does not prove
that Apple's extensions, notifications or audio services work on a phone.

Record the app commit/build, device, iOS version, date, selected apps, outcome of
each case and relevant unified logs. Mark cases PASS, FAIL or NOT RUN; do not
count a Simulator result as a device pass. Use a test device with no important
existing OutLoud configuration. No transcripts or app tokens need to be logged.

## Preparation

1. Install the development build with all three extensions and matching App
   Group / Family Controls entitlements. Run the OutLoud unit tests on the phone
   so the model-inference test can run with Apple's downloaded language asset.
   Simulator-only UI tests skip on a phone.
2. Select two individual apps, A and B. Include an app outside the auto-return
   list. Enable Screen Time, microphone and Speech Recognition permissions.
3. Keep Console.app open with subsystem `com.clarkohlenbusch.outloud`.

## Setup and returning to apps

- Complete setup with all mappings left on Return manually. Both apps should
  be protected. Unlock each and use the displayed gesture to switch back.
- Map a supported app, leave the other manual, and verify each return path.
  Remove the mapping and confirm manual return persists after relaunch.
- For an automatic destination that cannot open, confirm the user can still
  switch back manually; record any missing or confusing fallback instructions.

## Speech, cancellation and recovery

- In Own words mode, say a valid acknowledgment normally. Acceptance should
  happen after a pause and final recognition, once per challenge.
- Say “I am making a bad choice but I need this for work” as one uninterrupted
  utterance. Also try “I am not making a bad choice” and “I am making a good
  choice.” None should unlock. Test questions and quoted prompts as well.
- In Specific phrases mode, test the saved phrase, a contraction, an unrelated
  phrase, and added negation. Verify legitimate custom wording still works.
- Test with a headset and background noise. If automatic end-of-speech does not
  trigger, tap Done speaking. The app should finish checking or show a retryable
  error, never remain indefinitely in Checking phrase.
- Deny microphone permission, then Speech Recognition permission in a separate
  run. Confirm an explanation appears, cancel works, and retry succeeds after
  restoring permission in Settings. Cancel while a permission prompt is open;
  allowing it afterward must not start hidden recording.
- Interrupt capture by backgrounding the app or taking a call. Reopen and
  confirm the user can complete or retry the pause. Repeat with no network after
  the on-device assets are available. Audio must not use server fallback.
- Reopen OutLoud with a pending shield challenge, then cancel it. Reopening again
  must not resurrect the cancelled challenge. Practice must not unlock any app.

- For speech-service failures 1107/1101, verify one reconnect, the instruction
  to repeat the full phrase, and acceptance only of a fresh final result. A
  repeated failure must stop with Couldn’t listen and a working Try again.
- Use Settings > Developer > Reset Media Services during capture. Verify no
  automatic recording follows the reset; Try again must start a fresh session.
  Also cancel/background during Reconnecting and confirm recording stays off.
  See [the error 1107 investigation](SPEECH_1107_INVESTIGATION.md).

## Independent access windows

- Choose a 15-minute timer. Unlock A at time T, then B at T+5 minutes. B must
  remain protected until its own phrase succeeds; unlocking B must not re-lock A.
  At T+15, A must re-lock while B remains available until T+20.
- Repeat while OutLoud stays backgrounded, then after terminating OutLoud. The
  monitor extension should restore the shields; reopening OutLoud should also
  reconcile overdue windows. Record actual delivery timing.
- Enable Every visit with the documented Is Closed / Run Immediately Shortcut.
  Leaving an app must re-arm protection. Repeat in timer mode: the Shortcut must
  not cancel timed access. Disable protection and verify expiry/Shortcut
  callbacks do not re-enable it.
- For a build upgraded while an older access window is open, verify that the
  legacy monitor still restores protection and does not revoke newer windows.

## Reminders

- With protection off, test 1-, 5- and 10-minute cadences through at least two
  notifications each. Totals must match the cadence. Switch between A and B:
  their daily foreground-use totals must advance independently.
- After a five-minute reminder, switch to ten minutes. Confirm the next reminder
  is at ten cumulative minutes and a later reminder arrives at twenty.
- Relaunch OutLoud during the day and confirm totals continue. Cross actual
  midnight with reminders enabled; the next day's first milestone must start
  from the selected cadence. Changing the clock is not equivalent to this test.
- Disable reminders immediately after an alert. No later threshold should
  deliver another. Re-enable and verify monitoring resumes.
- Verify notification permission denial, Focus / Time Sensitive behavior and
  replacement of the previous delivered reminder. On a supported older iOS
  version without direct shield-to-app opening, also verify the challenge
  notification fallback and the behavior when notifications are denied.

## Automated fault coverage

`SpeechFlowTests` inject permission denial, unavailable recognition, stale
callbacks and missing final results. `AccessFlowTests` inject repeated monitor
failures, stale expiry callbacks and app relaunch. `ReminderFlowTests` drive the
same handler used by the extension through rescheduling and recovery. The UI
suite injects one unlock failure to verify the visible retry path. These cover
faults that are difficult to trigger reliably on a phone; they do not measure
the reliability or timing of the actual iOS services.
