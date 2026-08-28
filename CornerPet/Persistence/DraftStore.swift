import Foundation
import SwiftData

@MainActor
protocol DraftStoring: AnyObject {
    var onWriteFailure: ((Error) -> Void)? { get set }
    var onWriteSuccess: (() -> Void)? { get set }
    func restore() throws -> DraftSnapshot
    func stage(text: String, updatedAt: Date)
    func flush() throws
    func clear(updatedAt: Date) throws
}

@MainActor
protocol DraftWriteCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol DraftWriteScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DraftWriteCancellation
}

@MainActor
final class MainRunLoopDraftWriteScheduler: DraftWriteScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DraftWriteCancellation {
        MainRunLoopDraftWriteCancellation(delay: delay, action: action)
    }
}

@MainActor
final class DraftStore: DraftStoring {
    var onWriteFailure: ((Error) -> Void)?
    var onWriteSuccess: (() -> Void)?

    private let context: ModelContext
    private let scheduler: any DraftWriteScheduling
    private let debounce: TimeInterval
    private let fetchDrafts: (ModelContext, FetchDescriptor<Draft>) throws -> [Draft]
    private let save: (ModelContext) throws -> Void
    private var pending: DraftSnapshot?
    private var scheduledWrite: (any DraftWriteCancellation)?

    convenience init(
        context: ModelContext,
        scheduler: any DraftWriteScheduling = MainRunLoopDraftWriteScheduler(),
        debounce: TimeInterval = 0.250,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.init(
            context: context,
            scheduler: scheduler,
            debounce: debounce,
            fetchDrafts: { try $0.fetch($1) },
            save: save
        )
    }

    init(
        context: ModelContext,
        scheduler: any DraftWriteScheduling,
        debounce: TimeInterval,
        fetchDrafts: @escaping (ModelContext, FetchDescriptor<Draft>) throws -> [Draft],
        save: @escaping (ModelContext) throws -> Void
    ) {
        self.context = context
        self.scheduler = scheduler
        self.debounce = debounce
        self.fetchDrafts = fetchDrafts
        self.save = save
    }

    func restore() throws -> DraftSnapshot {
        if let pending {
            return pending
        }

        let drafts = try fetchDraftsNewestFirst()
        guard let draft = drafts.first else {
            return try performWrite {
                let draft = Draft()
                context.insert(draft)
                try saveChanges()
                return draft.snapshot
            }
        }

        if drafts.count > 1 {
            try performWrite {
                for duplicate in drafts.dropFirst() {
                    context.delete(duplicate)
                }
                try saveChanges()
            }
        }

        return draft.snapshot
    }

    func stage(text: String, updatedAt: Date) {
        pending = DraftSnapshot(text: text, updatedAt: updatedAt)
        scheduledWrite?.cancel()
        scheduledWrite = scheduler.schedule(after: debounce) { [weak self] in
            self?.performScheduledFlush()
        }
    }

    func flush() throws {
        cancelScheduledWrite()
        guard let snapshotToWrite = pending else { return }
        pending = nil

        try performWrite(onFailure: { [self] in
            if pending == nil {
                pending = snapshotToWrite
            }
        }) {
            let draft = try prepareSingletonForMutation()
            draft.text = snapshotToWrite.text
            draft.updatedAt = snapshotToWrite.updatedAt
            try saveChanges()
        }
    }

    func clear(updatedAt: Date) throws {
        cancelScheduledWrite()
        var snapshotToRetainOnFailure = pending
        pending = nil

        try performWrite(onFailure: { [self] in
            if pending == nil {
                pending = snapshotToRetainOnFailure
            }
        }) {
            let draft = try prepareSingletonForMutation()
            snapshotToRetainOnFailure = snapshotToRetainOnFailure ?? draft.snapshot
            draft.text = ""
            draft.updatedAt = updatedAt
            try saveChanges()
        }
    }

    private func performScheduledFlush() {
        try? flush()
    }

    private func cancelScheduledWrite() {
        scheduledWrite?.cancel()
        scheduledWrite = nil
    }

    private func fetchDraftsNewestFirst() throws -> [Draft] {
        let descriptor = FetchDescriptor<Draft>(sortBy: [
            SortDescriptor(\Draft.updatedAt, order: .reverse),
            SortDescriptor(\Draft.text, order: .forward)
        ])
        return try fetchDrafts(context, descriptor)
    }

    private func prepareSingletonForMutation() throws -> Draft {
        let drafts = try fetchDraftsNewestFirst()
        let draft: Draft

        if let existing = drafts.first {
            draft = existing
            for duplicate in drafts.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            draft = Draft()
            context.insert(draft)
        }

        return draft
    }

    private func performWrite<T>(
        onFailure: () -> Void = {},
        _ operation: () throws -> T
    ) throws -> T {
        do {
            let result = try operation()
            onWriteSuccess?()
            return result
        } catch {
            context.rollback()
            onFailure()
            onWriteFailure?(error)
            throw error
        }
    }

    private func saveChanges() throws {
        try save(context)
    }
}

@MainActor
private final class MainRunLoopDraftWriteCancellation: NSObject, DraftWriteCancellation {
    private var timer: Timer?
    private var action: (@MainActor () -> Void)?

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init()

        let timer = Timer(
            timeInterval: delay,
            target: self,
            selector: #selector(fire),
            userInfo: nil,
            repeats: false
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    @objc
    private func fire() {
        let action = action
        self.action = nil
        timer?.invalidate()
        timer = nil
        action?()
    }
}
