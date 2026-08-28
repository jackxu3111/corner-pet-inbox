import Observation

@MainActor
@Observable
final class CaptureShellViewModel {
    private(set) var selectedDestination: CaptureDestination = .inbox

    func select(_ destination: CaptureDestination) {
        selectedDestination = destination
    }
}
