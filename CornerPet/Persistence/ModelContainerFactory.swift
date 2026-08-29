import Foundation
import SwiftData

@MainActor
enum ModelContainerFactory {
    private static var schema: Schema {
        Schema(versionedSchema: CornerPetSchemaV1.self)
    }

    static func makeProduction() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CornerPetMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CornerPetMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func make(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CornerPetMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
