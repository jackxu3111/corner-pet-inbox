import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class ModelContainerFactoryTests: XCTestCase {
    func testSchemaAndMigrationPlanStartAtV1WithoutSpeculativeStages() {
        XCTAssertEqual(CornerPetSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(CornerPetMigrationPlan.schemas.count, 1)
        XCTAssertEqual(
            CornerPetMigrationPlan.schemas.first?.versionIdentifier,
            CornerPetSchemaV1.versionIdentifier
        )
        XCTAssertTrue(CornerPetMigrationPlan.stages.isEmpty)
    }

    func testFactoryAttachesTheMigrationPlan() throws {
        let container = try ModelContainerFactory.makeInMemory()

        XCTAssertNotNil(container.migrationPlan)
    }

    func testOpeningTask12LegacyStorePreservesEveryPersistedFieldAcrossReopen() throws {
        let storeURL = try copyLegacyFixtureToTemporaryDirectory()

        try assertLegacyFixtureContents(at: storeURL)
        try assertLegacyFixtureContents(at: storeURL)
    }

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

    private func copyLegacyFixtureToTemporaryDirectory() throws -> URL {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/Task12Legacy.store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CornerPetLegacyMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "CornerPetContent.store")
        try FileManager.default.copyItem(at: fixtureURL, to: storeURL)
        return storeURL
    }

    private func assertLegacyFixtureContents(at storeURL: URL) throws {
        let container = try ModelContainerFactory.make(at: storeURL)
        let context = ModelContext(container)

        let drafts = try context.fetch(FetchDescriptor<Draft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.text, "legacy draft")
        XCTAssertEqual(drafts.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        let items = try context.fetch(FetchDescriptor<IdeaItem>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(items.count, 3)

        let expected: [(String, ItemBucket, String, TimeInterval)] = [
            ("00000000-0000-0000-0000-000000000001", .inbox, "legacy inbox", 1_700_000_100),
            ("00000000-0000-0000-0000-000000000002", .archive, "legacy archive", 1_700_000_200),
            ("00000000-0000-0000-0000-000000000003", .favorite, "legacy favorite", 1_700_000_300),
        ]

        for (item, fixture) in zip(items, expected) {
            let createdAt = Date(timeIntervalSince1970: fixture.3)
            XCTAssertEqual(item.id, try XCTUnwrap(UUID(uuidString: fixture.0)))
            XCTAssertEqual(item.bucket, fixture.1)
            XCTAssertEqual(item.text, fixture.2)
            XCTAssertEqual(item.createdAt, createdAt)
            XCTAssertEqual(item.updatedAt, createdAt.addingTimeInterval(10))
            XCTAssertEqual(item.movedAt, createdAt.addingTimeInterval(20))
        }
    }
}
