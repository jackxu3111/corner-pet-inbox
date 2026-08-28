import Observation

@MainActor
@Observable
final class CaptureShellViewModel {
    private(set) var selectedDestination: CaptureDestination = .inbox
    private(set) var searchFocusRequest = 0

    func select(_ destination: CaptureDestination) {
        selectedDestination = destination
    }

    @discardableResult
    func requestSearchFocus() -> Bool {
        switch selectedDestination {
        case .favorites, .archive:
            searchFocusRequest &+= 1
            return true
        case .inbox, .settings:
            return false
        }
    }
}
