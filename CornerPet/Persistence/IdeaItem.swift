import Foundation
import SwiftData

enum ItemBucket: String, Codable, CaseIterable {
    case inbox
    case archive
    case favorite
}

@Model
final class IdeaItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var bucketRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var movedAt: Date

    var bucket: ItemBucket {
        get { ItemBucket(rawValue: bucketRawValue) ?? .inbox }
        set { bucketRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        text: String,
        bucket: ItemBucket = .inbox,
        createdAt: Date,
        updatedAt: Date,
        movedAt: Date
    ) {
        self.id = id
        self.text = text
        self.bucketRawValue = bucket.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.movedAt = movedAt
    }

    var snapshot: IdeaItemSnapshot {
        IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: bucket,
            createdAt: createdAt,
            updatedAt: updatedAt,
            movedAt: movedAt
        )
    }
}

struct IdeaItemSnapshot: Identifiable, Equatable {
    let id: UUID
    let text: String
    let bucket: ItemBucket
    let createdAt: Date
    let updatedAt: Date
    let movedAt: Date
}
