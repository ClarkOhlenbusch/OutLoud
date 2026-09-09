import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import XCTest
@testable import OutLoud

final class FakeScreenTime {
    var date = Date(timeIntervalSince1970: 1_800_050_400)
    var monitors: [DeviceActivityName: [DeviceActivityEvent.Name: DeviceActivityEvent]] = [:]
    var schedules: [DeviceActivityName: DeviceActivitySchedule] = [:]
    var shields = FamilyActivitySelection()
    var failuresRemaining = 0
    var failAtStart: Int?
    var starts = 0

    var client: ScreenTimeClient {
        ScreenTimeClient(now: { self.date }, activities: { Array(self.monitors.keys) },
            start: { name, schedule, events in
                self.starts += 1
                if self.failuresRemaining > 0 || self.starts == self.failAtStart {
                    self.failuresRemaining = max(0, self.failuresRemaining - 1)
                    throw NSError(domain: "FakeScreenTime", code: 1)
                }
                self.monitors[name] = events
                self.schedules[name] = schedule
            },
            stop: { names in names.forEach { self.monitors.removeValue(forKey: $0); self.schedules.removeValue(forKey: $0) } },
            applyShields: { self.shields = $0 },
            clearShields: { self.shields = FamilyActivitySelection() })
    }
}

class ScreenTimeFlowTestCase: XCTestCase {
    var system: FakeScreenTime!
    private var suiteName: String!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "outloud.tests.\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedSettings.testStorage = (try XCTUnwrap(UserDefaults(suiteName: suiteName)), directory)
        SharedSettings.acceptsSimilarAcknowledgements = false
        system = FakeScreenTime()
        ScreenTimeClient.current = system.client
        NotificationPermissionClient.request = { false }
    }

    override func tearDownWithError() throws {
        SharedSettings.testStorage?.defaults.removePersistentDomain(forName: suiteName)
        SharedSettings.testStorage = nil
        ScreenTimeClient.current = .live
        NotificationPermissionClient.request = NotificationPermissionClient.live
        try FileManager.default.removeItem(at: directory)
        system = nil
        try super.tearDownWithError()
    }

    func token(_ value: UInt8) throws -> ApplicationToken {
        // Synthetic opaque tokens never reach Apple's real APIs in these tests.
        let data = try JSONEncoder().encode(["data": Data([value])])
        return try JSONDecoder().decode(ApplicationToken.self, from: data)
    }
}

@MainActor
final class FakeSpeechCapture: SpeechCapture {
    var permissions: [(Bool) -> Void] = []
    var receivers: [(SpeechCaptureEvent) -> Void] = []
    var startError: Error?
    var starts = 0
    var onStart: (() -> Void)?
    var finishes = 0
    var stops = 0
    func requestPermissions(_ completion: @escaping (Bool) -> Void) { permissions.append(completion) }
    func start(phrases: [String], receive: @escaping (SpeechCaptureEvent) -> Void) throws {
        starts += 1
        if let startError { throw startError }
        receivers.append(receive)
        onStart?()
    }
    func finish() { finishes += 1 }
    func stop() { stops += 1 }
}
