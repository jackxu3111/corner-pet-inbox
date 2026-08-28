import Foundation
import SwiftData

private enum ItemStoreFixtureError: Error {
    case permanentDeleteFailed
}

@MainActor
protocol ItemStoring: AnyObject {
    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot?
    func fetchInbox() throws -> [IdeaItemSnapshot]
}

@MainActor
protocol InboxItemStoring: ItemStoring {
    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot?
}

@MainActor
protocol ItemLifecycleStoring: ItemStoring {
    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot]
    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot?
    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot?
    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool
}

@MainActor
protocol ArchiveItemStoring: AnyObject {
    func fetchArchive() throws -> [IdeaItemSnapshot]
}

@MainActor
final class ItemStore: InboxItemStoring, ArchiveItemStoring, ItemLifecycleStoring {
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void
    private let failPermanentDeletes: Bool

    init(
        context: ModelContext,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() },
        failPermanentDeletes: Bool = false
    ) {
        self.context = context
        self.save = save
        self.failPermanentDeletes = failPermanentDeletes
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }

        let item = IdeaItem(
            text: normalizedText,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        )
        context.insert(item)

        return try saveMutation(rollback: { context.delete(item) }) { item.snapshot }
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        try fetchItems(in: .inbox)
    }

    func fetchArchive() throws -> [IdeaItemSnapshot] {
        try fetchItems(in: .archive)
    }

    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot] {
        let bucketRawValue = bucket.rawValue
        var descriptor = FetchDescriptor<IdeaItem>(
            predicate: #Predicate { item in
                item.bucketRawValue == bucketRawValue
            }
        )
        descriptor.sortBy = if bucket == .inbox {
            [
                SortDescriptor(\IdeaItem.createdAt, order: .reverse),
                SortDescriptor(\IdeaItem.id, order: .forward)
            ]
        } else {
            [
                SortDescriptor(\IdeaItem.movedAt, order: .reverse),
                SortDescriptor(\IdeaItem.id, order: .forward)
            ]
        }
        return try context.fetch(descriptor).map(\.snapshot)
    }

    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        guard source != destination,
              let item = try fetchItem(id: id),
              item.bucket == source else {
            return nil
        }

        let originalBucket = item.bucket
        let originalUpdatedAt = item.updatedAt
        let originalMovedAt = item.movedAt
        return try saveMutation(rollback: {
            item.bucket = originalBucket
            item.updatedAt = originalUpdatedAt
            item.movedAt = originalMovedAt
        }) {
            item.bucket = destination
            item.updatedAt = date
            item.movedAt = date
            return item.snapshot
        }
    }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        guard let item = try fetchItem(id: id), item.bucket == expectedBucket else {
            return nil
        }

        let originalText = item.text
        let originalUpdatedAt = item.updatedAt
        return try saveMutation(rollback: {
            item.text = originalText
            item.updatedAt = originalUpdatedAt
        }) {
            item.text = text
            item.updatedAt = date
            return item.snapshot
        }
    }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool {
        guard let item = try fetchItem(id: id), item.bucket == expectedBucket else {
            return false
        }
        if failPermanentDeletes {
            throw ItemStoreFixtureError.permanentDeleteFailed
        }

        return try saveMutation(rollback: { context.insert(item) }) {
            context.delete(item)
            return true
        }
    }

    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot? {
        try moveItem(id: id, from: .inbox, to: .archive, at: date)
    }

    private func fetchItem(id: UUID) throws -> IdeaItem? {
        let itemID = id
        let descriptor = FetchDescriptor<IdeaItem>(
            predicate: #Predicate { item in
                item.id == itemID
            }
        )
        return try context.fetch(descriptor).first
    }

    private func saveMutation<Value>(
        rollback: () -> Void,
        mutation: () -> Value
    ) throws -> Value {
        let value = mutation()
        do {
            try save(context)
            return value
        } catch {
            rollback()
            throw error
        }
    }
}
