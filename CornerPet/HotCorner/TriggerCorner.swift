import Foundation

enum TriggerCorner: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct TriggerCornerStore {
    static let storageKey = "CornerPet.triggerCorner"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TriggerCorner {
        guard let rawValue = defaults.string(forKey: Self.storageKey),
              let corner = TriggerCorner(rawValue: rawValue) else {
            return .topLeft
        }
        return corner
    }

    func save(_ corner: TriggerCorner) {
        defaults.set(corner.rawValue, forKey: Self.storageKey)
    }
}
