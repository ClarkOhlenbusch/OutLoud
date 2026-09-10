"""Fail CI if critical real-model/UI tests were omitted, skipped, or failed."""

import json
import subprocess
import sys

required = {
    "PhraseMatcherTests/testEveryRequiredAcknowledgementRegressionWithBundledModel()",
    "PhraseMatcherTests/testBasicAcknowledgementsWithSpeechPunctuation()",
    "AccessFlowTests/testRealAcknowledgementReleasesOnlyRequestedAppAndIgnoresLateSpeech()",
    "SpeechFlowTests/testRepeatedRejectionsStopAfterThreeAttemptsAndManualRetryResetsBudget()",
    "CoreFlowUITests/testRealClassifierAcceptsBadChoiceThroughChallengeUI()",
    "CoreFlowUITests/testRealClassifierAcceptsValidSpeechAfterRejections()",
    "CoreFlowUITests/testModelParaphraseUnlocksThroughChallengeUI()",
    "CoreFlowUITests/testDoneSpeakingUsesRealClassifierAndUnlocks()",
    "CoreFlowUITests/testRealClassifierRepeatedRejectionsStopAndRetryCanUnlock()",
}


def results(nodes):
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            yield node["nodeIdentifier"], node.get("result")
        yield from results(node.get("children", []))


def main():
    report = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[1]
    ]))
    actual = dict(results(report["testNodes"]))
    missing = {name: actual.get(name, "Missing") for name in required if actual.get(name) != "Passed"}
    if missing:
        raise SystemExit("Required regressions did not pass: " + json.dumps(missing, indent=2))
    print(f"Verified all {len(required)} required regression tests ran and passed.")


if __name__ == "__main__":
    main()
