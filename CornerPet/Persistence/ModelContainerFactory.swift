import Foundation
import SwiftData

@MainActor
enum ModelContainerFactory {
    private static var schema: Schema {
        Schema([Draft.self, IdeaItem.self])
    }

    static func makeProduction() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func make(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
