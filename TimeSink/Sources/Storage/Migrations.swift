import Foundation
import GRDB

/// Manages database schema migrations for TimeSink.
struct AppMigrations {

    /// Registers all migrations with the given migrator.
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_createSchema") { db in
            // Categories table
            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("color", .text).notNull().defaults(to: "#888888")
                t.column("isProductive", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            // Activity records table
            try db.create(table: "activity_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text).notNull().defaults(to: "")
                t.column("detail", .text)
                t.column("detailType", .text).notNull().defaults(to: "app")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("durationSeconds", .integer)
                t.column("isIdle", .boolean).notNull().defaults(to: false)
                t.column("categoryId", .integer)
                    .references("categories", onDelete: .setNull)
                t.column("categorizedAt", .datetime)
            }

            // Indexes for common queries
            try db.create(
                index: "idx_activity_records_startedAt",
                on: "activity_records",
                columns: ["startedAt"]
            )
            try db.create(
                index: "idx_activity_records_categoryId",
                on: "activity_records",
                columns: ["categoryId"]
            )
            try db.create(
                index: "idx_activity_records_appName",
                on: "activity_records",
                columns: ["appName"]
            )

            // Categorization log table
            try db.create(table: "categorization_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batchSize", .integer).notNull()
                t.column("processedAt", .datetime).notNull()
                t.column("modelUsed", .text).notNull()
                t.column("promptTokens", .integer).notNull().defaults(to: 0)
                t.column("completionTokens", .integer).notNull().defaults(to: 0)
            }

            // Seed default categories
            for category in Category.defaults {
                var cat = category
                try cat.insert(db)
            }
        }

        migrator.registerMigration("v2_addCategoryRealm") { db in
            try db.alter(table: "categories") { t in
                t.add(column: "realm", .text)
            }
        }
    }
}
