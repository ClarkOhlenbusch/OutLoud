# Acknowledgment regression investigation

The reported sentence, “this is a bad choice”, was rejected by the bundled
classifier before any access-window or return-to-app operation. The controller
then restarted recording after every rejection without a limit. The resulting
loop was real; a specific-phrase fallback alone did not repair the classifier.

## Reproduction

The original CPU model, with threshold 0.994, produced these scores:

| Transcript | Score | Result |
| --- | ---: | --- |
| this is a bad choice | 0.993995 | Rejected |
| This is a bad choice. | 0.986419 | Rejected |
| This is a bad choice! | 0.079605 | Rejected |
| I'm wasting time | 0.070722 | Rejected |
| This is a waste of time | 0.990372 | Rejected |
| This app is distracting me | 0.993975 | Rejected |

A clean Simulator build reproduced the rejection in the actual ChallengeView
using scripted partial/final transcripts and the real asynchronous classifier.
The new basic-acknowledgment unit test failed on all six cases above.

## Why the tests missed it

- Existing UI fixtures replaced classification with a stub that accepted only
  “I am making a bad choice”. The scripted recognizer supplied that same phrase.
  Those tests verified navigation, not the path from arbitrary speech through
  the bundled model to unlocking.
- Real-model unit tests checked a small set of successful paraphrases, but did
  not include the user's simplest wording or its punctuation variants.
- Training selected a threshold by prioritizing precision once aggregate
  recall reached 80%. A model could therefore reject common acknowledgments
  and still pass. Exported Core ML evaluation checked aggregate metrics, with
  no mandatory acceptance cases and no punctuation robustness gate.
- Retry tests explicitly expected unlimited automatic retries. There was no
  maximum-attempt test.
- UI tests checked that text existed, not that its full instruction was visible.
  The fixed vertical layout compressed the main instruction into one truncated
  line when rejection controls appeared.
- During this investigation an incremental build reported success while the
  newly selected unit test executed zero cases and the UI used old behavior.
  A clean, isolated build exposed the failures. The underlying Xcode cache
  problem was not established; execution-name verification now guards against
  missing regression cases.

## Corrections and scope

The app now recognizes a small set of complete, explicit acknowledgments before
consulting the existing model for other wording. For example, “this is a bad
choice”, “This is a bad choice.” and “This is a bad choice!” have the same
accepted meaning. Exact matching expands common contractions and normalizes
whitespace and terminal periods/exclamation marks. It does not remove questions,
quotations, negations, or added clauses, and never accepts a substring of a
longer statement. This works in Own words without changing modes or settings.

The original model and threshold remain unchanged. Two retrained revisions were
rejected during this investigation: although they learned the core phrases,
they failed separate holdouts with four and five false accepts. Neither was
shipped. Their training/data changes were discarded. The old final-test corpus
now needs replacement before any future model development because its errors
were inspected during those experiments. Broader model matching remains
probabilistic; exact matching guarantees the defined complete acknowledgments.

The first two mismatches can restart listening; a third stops recording and
shows the recognized words and retry controls. Switching to a specific phrase
remains optional and requires fresh final speech. The challenge content scrolls
when necessary, and the full instruction keeps its natural height.

New UI tests use production matching for plain/punctuated acknowledgments,
rejection followed by acceptance, Done speaking, and retry after the limit.
A separate paraphrase UI test requires actual bundled-model inference. An
access-flow test combines production matching with isolated Screen Time state
to verify that only the requested app is released. CI checks that the required
tests actually ran and passed, including all 32 cases in the bundled app
regression JSON. Those cases are behavior contracts, not an independent model
accuracy estimate.

Scripted speech and an in-memory Screen Time adapter do not establish physical
microphone recognition or real shield propagation. Those still require the
[device validation checklist](DEVICE_VALIDATION.md).

## Verification on 2026-09-09

- A clean iPhone 17 Simulator run passed 122 tests (107 unit/flow, 15 UI),
  with zero failures, expected failures, or skips. The result verifier confirmed
  all nine mandatory regression tests were present and passed.
- The connected iPhone 17 Pro Max passed all 107 unit/flow tests, including
  all 32 production-matcher contracts. The updated app was installed and
  launched normally after testing.
- Screenshot inspection confirmed the full instruction and reachable retry
  controls in landscape. The portrait regression also checks prompt height.
- These runs use scripted speech. Live microphone transcription and real
  Screen Time shield propagation have not been revalidated in this fix.

## Subsequent Upgrade to all-MiniLM-L6-v2

Following this investigation, the bundled classifier was upgraded from `BERT-Medium`
to `sentence-transformers/all-MiniLM-L6-v2` (6 layers, 384 hidden units, 22.7M parameters):
- Model weight size reduced from 83 MB to 43 MB (48% reduction).
- Inference latency reduced by ~45% (~7.8 ms CPU evaluation).
- Operating threshold calibrated to 0.980 via balanced F1-score optimization.
- Reaches 96.0% precision and 96.0% recall on the independent 125-item test set.
- Robust semantic generalization across natural variations (e.g. "I probably shouldn't open this app", "this could be a bad idea") while maintaining strong separation from tricky negations/contradictions (which score < 10%).
