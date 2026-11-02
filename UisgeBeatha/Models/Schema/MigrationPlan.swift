import SwiftData

/// Every schema the app has ever shipped, oldest first, and how to get from
/// each to the next. Phase 3 appends `SchemaV2` and a stage here.
enum UisgeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
