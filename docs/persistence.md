# CornerPet Persistence and Migration

## Current contract

CornerPet stores local content with SwiftData and does not use CloudKit. Task 12.5 establishes the already shipped model as `CornerPetSchemaV1` with version `1.0.0`:

- `Draft`: `text`, `updatedAt`
- `IdeaItem`: unique `id`, `text`, `bucketRawValue`, `createdAt`, `updatedAt`, `movedAt`

`Draft` and `IdeaItem` remain available through top-level type aliases so the rest of the app does not depend on schema-version nesting. The production configuration remains named `CornerPetContent`; Task 12.5 does not relocate or recreate the store.

Every `ModelContainerFactory` entry point constructs `Schema(versionedSchema: CornerPetSchemaV1.self)` and supplies `CornerPetMigrationPlan.self`. The plan currently contains only V1 and therefore has no migration stages. Empty stages are intentional: there is no data-shape change to migrate in Task 12.5.

Apple defines `VersionedSchema` as the model set and identifier for one schema version, and `SchemaMigrationPlan` as the ordered schemas and stages that describe evolution:

- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)

## Existing-user compatibility evidence

`CornerPetTests/Fixtures/Task12Legacy.store` was generated once from the Task 12 unversioned `Schema([Draft.self, IdeaItem.self])` implementation before the production models were moved into V1. It contains synthetic data only:

- one draft with a fixed timestamp;
- one inbox item;
- one archived item;
- one favorite item;
- fixed UUIDs and distinct creation, update, and move timestamps.

The fixture was checkpointed into a single SQLite store and passed `PRAGMA integrity_check`. `ModelContainerFactoryTests` copies it to a temporary directory, opens it through the versioned factory, checks every persisted field, closes it, then opens the migrated copy again and repeats the checks. Tests never modify the checked-in fixture.

This is stronger than creating a new V1 store: it verifies that the actual pre-versioning entity metadata remains compatible after the models are encapsulated.

## Adding a future V2

Do not edit V1 model properties. Treat every released schema as immutable.

For a real data-shape change:

1. Copy the V1 models into `CornerPetSchemaV2` and make only the required V2 change.
2. Give V2 a higher identifier, such as `Schema.Version(2, 0, 0)`.
3. Append V2 to `CornerPetMigrationPlan.schemas`.
4. Add one `.lightweight` or `.custom` `MigrationStage` from V1 to V2 based on the actual change.
5. Add a V1 fixture containing boundary data and a test that opens it through the new current schema.
6. Verify exact values after migration and after a second reopen.
7. Test migration failure against a copied store and confirm the original remains intact.

Apple documents lightweight and custom stages in [MigrationStage](https://developer.apple.com/documentation/swiftdata/migrationstage). Do not add placeholder future fields or empty future versions merely to reserve them.

## Failure and backup policy

- A migration error must propagate to the app's existing startup error handling.
- Never delete, truncate, recreate, or silently replace the production store after a migration failure.
- Diagnose and repair migration logic against a copy of the affected store.
- Before a future release that changes the schema, retain a backup of representative previous-version stores and run the migration suite on every supported upgrade path.
- Before manually testing a migration with personal data, quit CornerPet and make a recoverable copy of its application-support data. Restore only while the app is not running.

Task 12.5 does not add a rollback migration. SwiftData migration plans move stores forward; operational rollback is restoration of a pre-upgrade backup with the matching older app build.
