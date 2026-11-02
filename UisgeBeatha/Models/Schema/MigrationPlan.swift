import SwiftData

/// Every schema the app has ever shipped, oldest first, and how to get from
/// each to the next.
///
/// V1 to V2 is lightweight: V2 only adds optional attributes
/// (`stockPhotoAttribution`, `lastTastedDate`, `priceMinorUnits`), an
/// optional `photos` relationship and the `BottlePhoto` entity. Moving
/// existing photo files into `BottlePhoto` rows is not part of the
/// migration itself; `PhotoMigrator` does it after launch, and only
/// deletes a file once its row is safely saved.
enum UisgeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
