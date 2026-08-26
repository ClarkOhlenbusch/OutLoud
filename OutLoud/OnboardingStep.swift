import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case screenTime
    case apps
    case phrase
    case everyVisit
    case usageReminders
    case ready

    static let progressCount = allCases.count - 1

    init(storedValue: Int) {
        self = Self(rawValue: storedValue) ?? .welcome
    }

    var previous: Self {
        Self(rawValue: max(Self.welcome.rawValue, rawValue - 1)) ?? .welcome
    }
}
