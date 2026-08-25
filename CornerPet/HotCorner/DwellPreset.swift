import Foundation

enum DwellPreset: TimeInterval, CaseIterable {
    case fast = 0.5
    case standard = 0.6
    case conservative = 0.7

    static let `default`: Self = .standard
}
