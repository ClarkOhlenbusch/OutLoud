import XCTest

final class CoreFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
#if !targetEnvironment(simulator)
        throw XCTSkip("UI fixtures run in Simulator; use docs/DEVICE_VALIDATION.md on a physical iPhone.")
#else
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["OUTLOUD_UI_TEST_ID"] = UUID().uuidString
#endif
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ scenario: String) {
        app.launchEnvironment["OUTLOUD_UI_TEST_SCENARIO"] = scenario
        app.launch()
    }

    func testOnboardingCompletesWithoutAutoReturnMappings() {
        launch("onboarding")
        app.buttons["Continue"].tap()
        let continueSetup = app.navigationBars.buttons["Continue"]
        XCTAssertTrue(continueSetup.waitForExistence(timeout: 5))
        XCTAssertTrue(continueSetup.isEnabled)
        continueSetup.tap()
        app.buttons["Practice"].tap()
        XCTAssertTrue(app.buttons["Continue setup"].waitForExistence(timeout: 5))
        app.buttons["Continue setup"].tap()
        app.buttons["Set up later"].tap()
        app.buttons["Not now"].tap()
        app.buttons["Turn on protection"].tap()
        XCTAssertTrue(app.staticTexts["Protection is on"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manual return"].exists)
    }

    func testMixedReturnMappingsCanBeRemoved() {
        launch("mappings")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Auto-return")).firstMatch.tap()
        let mappings = app.buttons.matching(identifier: "return-mapping")
        XCTAssertEqual(mappings.count, 2)
        mappings.element(boundBy: 0).tap()
        app.buttons["YouTube"].tap()
        XCTAssertEqual(mappings.matching(NSPredicate(format: "label CONTAINS %@", "Return manually")).count, 1)
        mappings.matching(NSPredicate(format: "label CONTAINS %@", "YouTube")).firstMatch.tap()
        app.buttons["manual-return-option"].tap()
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Manual return"].exists)
    }

    func testManualReturnAppearsAfterUnlock() {
        launch("manual-return")
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Swipe right along the bottom edge to go back."].exists)
    }

    func testAutomaticReturnOffersCorrectApp() {
        launch("automatic-return")
        XCTAssertTrue(app.buttons["Return to YouTube"].waitForExistence(timeout: 5))
    }

    func testFailedUnlockRetriesWithoutRestartingSpeech() {
        launch("unlock-failure")
        let retry = app.buttons["Try unlocking again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Couldn’t unlock"].exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
    }

    func testSpeechServiceInterruptionAutomaticallyRecovers() {
        launch("speech-interruption")
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
    }

    func testRejectedPhrasesAutomaticallyListenAgainAndUnlock() {
        launch("speech-rejection")
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["Restart listening"].exists)
    }

    func testRejectedOwnWordsCanSwitchToSpecificPhraseAndUnlock() {
        launch("speech-rejection-fallback")
        let fallback = app.buttons["Say a specific phrase instead"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unlocked"].exists)
        fallback.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Swipe right along the bottom edge to go back."].exists)
        XCTAssertFalse(fallback.exists)
    }

    func testRealClassifierAcceptsBadChoiceThroughChallengeUI() {
        for text in ["this is a bad choice", "This is a bad choice.", "This is a bad choice!"] {
            app.launchEnvironment["OUTLOUD_UI_TEST_TRANSCRIPT"] = text
            launch("real-own-words")
            XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 20), text)
            XCTAssertTrue(app.staticTexts["Swipe right along the bottom edge to go back."].exists)
            XCTAssertFalse(app.buttons["Say a specific phrase instead"].exists)
            app.terminate()
        }
    }

    func testRealClassifierAcceptsValidSpeechAfterRejections() {
        launch("real-own-words-retry")
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 20))
    }

    func testModelParaphraseUnlocksThroughChallengeUI() {
        app.launchEnvironment["OUTLOUD_UI_TEST_TRANSCRIPT"] = "I know scrolling would take me away from my plans"
        launch("real-own-words")
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 20))
    }

    func testDoneSpeakingUsesRealClassifierAndUnlocks() {
        launch("real-own-words-manual-end")
        let done = app.buttons["Done speaking"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unlocked"].exists)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 20))
    }

    func testRealClassifierRepeatedRejectionsStopAndRetryCanUnlock() {
        launch("real-own-words-rejection-limit")
        let retry = app.buttons["Restart listening"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Couldn’t match your words"].exists)
        XCTAssertTrue(app.staticTexts["Heard: “I need this for work”"].exists)
        XCTAssertFalse(app.staticTexts["Unlocked"].exists)
        let prompt = app.staticTexts["challenge-prompt"]
        // A single truncated line used to pass existence checks.
        XCTAssertGreaterThan(prompt.frame.height, 50)
        if !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(app.buttons["Say a specific phrase instead"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Repeated rejection controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 20))
    }

    func testRejectionControlsRemainReachableInLandscape() {
        launch("speech-rejection-limit")
        let retry = app.buttons["Restart listening"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let w = self.app.windows.firstMatch.frame.width
            let h = self.app.windows.firstMatch.frame.height
            return w > h || self.app.frame.width > self.app.frame.height
        }, object: nil)
        _ = XCTWaiter.wait(for: [rotated], timeout: 5)
        app.swipeUp()
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Landscape rejection controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
    }

    func testRepeatedSpeechInterruptionShowsHelpfulRetryAndRecovers() {
        launch("speech-interruption-repeated")
        let retry = app.buttons["Restart listening"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Couldn’t listen"].exists)
        XCTAssertTrue(app.staticTexts["“I am wasting my time on Instagram.”"].exists)
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speech recognition was interrupted")).firstMatch
        XCTAssertTrue(error.exists)
        XCTAssertFalse(app.staticTexts["Getting ready"].exists)
        XCTAssertFalse(app.staticTexts["Unlocked"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Speech interruption recovery exhausted"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        XCTAssertFalse(error.exists)
    }
}
