import Foundation
import Observation

enum ArchiveUndoError: Equatable {
    case restoreFailed
}

struct ArchiveUndoOffer: Equatable {
    let generation: Int
    let item: IdeaItemSnapshot
    let expiresAt: TimeInterval
}

@MainActor
@Observable
final class ArchiveUndoController {
    static let duration: TimeInterval = 5.0

    private(set) var offer: ArchiveUndoOffer?
    private(set) var error: ArchiveUndoError?

    var onUndoSucceeded: ((IdeaItemSnapshot) -> Void)?
    var onStateChanged: (() -> Void)?

    private let itemStore: any ItemLifecycleStoring
    private let scheduler: any HotCornerDeadlineScheduling
    private let clock: HotCornerClock
    private let dateProvider: () -> Date
    private var nextGeneration = 0
    private var expiryCancellation: (any HotCornerCancellation)?

    init(
        itemStore: any ItemLifecycleStoring,
        scheduler: any HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        clock: @escaping HotCornerClock = { ProcessInfo.processInfo.systemUptime },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.itemStore = itemStore
        self.scheduler = scheduler
        self.clock = clock
        self.dateProvider = dateProvider
    }

    func publish(_ item: IdeaItemSnapshot) {
        expiryCancellation?.cancel()
        expiryCancellation = nil
        nextGeneration &+= 1
        let generation = nextGeneration
        let expiresAt = clock() + Self.duration
        offer = ArchiveUndoOffer(generation: generation, item: item, expiresAt: expiresAt)
        error = nil
        onStateChanged?()
        expiryCancellation = scheduler.schedule(after: Self.duration) { [weak self] in
            self?.expire(generation: generation)
        }
    }

    func didArchive(_ item: IdeaItemSnapshot) {
        publish(item)
    }

    func undo() {
        guard let currentOffer = offer else { return }

        do {
            guard let restored = try itemStore.moveItem(
                id: currentOffer.item.id,
                from: .archive,
                to: .inbox,
                at: dateProvider()
            ) else {
                error = .restoreFailed
                onStateChanged?()
                return
            }

            expiryCancellation?.cancel()
            expiryCancellation = nil
            offer = nil
            error = nil
            onStateChanged?()
            onUndoSucceeded?(restored)
        } catch {
            self.error = .restoreFailed
            onStateChanged?()
        }
    }

    private func expire(generation: Int) {
        guard let currentOffer = offer,
              currentOffer.generation == generation,
              clock() >= currentOffer.expiresAt else {
            return
        }

        offer = nil
        expiryCancellation = nil
        onStateChanged?()
    }
}
