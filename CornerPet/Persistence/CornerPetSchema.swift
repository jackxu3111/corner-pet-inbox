import SwiftData

// Freeze every shipped model shape in a VersionedSchema before evolving it.
// Source: https://developer.apple.com/videos/play/wwdc2023/10195/
enum CornerPetSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Draft.self, IdeaItem.self]
    }
}

enum CornerPetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CornerPetSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
