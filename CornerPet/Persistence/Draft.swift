import Foundation
import SwiftData

@Model
final class Draft {
    var text: String
    var updatedAt: Date

    init(text: String = "", updatedAt: Date = .distantPast) {
        self.text = text
        self.updatedAt = updatedAt
    }

    var snapshot: DraftSnapshot {
        DraftSnapshot(text: text, updatedAt: updatedAt)
    }
}

struct DraftSnapshot: Equatable {
    let text: String
    let updatedAt: Date
}
