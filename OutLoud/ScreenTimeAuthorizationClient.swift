import Combine
import FamilyControls

struct ScreenTimeAuthorizationClient {
    var status: @MainActor () -> AuthorizationStatus
    var request: @MainActor () async throws -> Void
    var observe: @MainActor (@escaping (AuthorizationStatus) -> Void) -> AnyCancellable

    static var current = live
    static let live = ScreenTimeAuthorizationClient(
        status: { AuthorizationCenter.shared.authorizationStatus },
        request: { try await AuthorizationCenter.shared.requestAuthorization(for: .individual) },
        observe: { receive in
            AuthorizationCenter.shared.$authorizationStatus.sink(receiveValue: receive)
        }
    )
}
