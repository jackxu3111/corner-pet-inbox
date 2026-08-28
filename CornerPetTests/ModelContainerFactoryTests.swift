import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class ModelContainerFactoryTests: XCTestCase {
    func testInMemoryContainerRegistersDraftAndIdeaItem() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_000)

        context.insert(Draft(text: "draft", updatedAt: date))
        context.insert(IdeaItem(
            text: "idea",
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<IdeaItem>()).count, 1)
    }

    func testReopeningTheSameStoreURLRestoresDraftAndItem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CornerPetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("content.store")
        let date = Date(timeIntervalSince1970: 2_000)

        do {
            let first = try ModelContainerFactory.make(at: storeURL)
            let context = ModelContext(first)
            context.insert(Draft(text: "survives", updatedAt: date))
            context.insert(IdeaItem(
                text: "also survives",
                createdAt: date,
                updatedAt: date,
                movedAt: date
            ))
            try context.save()
        }

        let relaunched = try ModelContainerFactory.make(at: storeURL)
        let relaunchedContext = ModelContext(relaunched)
        XCTAssertEqual(try relaunchedContext.fetch(FetchDescriptor<Draft>()).map(\.text), ["survives"])
        XCTAssertEqual(try relaunchedContext.fetch(FetchDescriptor<IdeaItem>()).map(\.text), ["also survives"])
    }
}
