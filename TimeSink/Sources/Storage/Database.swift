import Foundation
import GRDB

/// Provides access to the TimeSink SQLite database.
///
/// Uses `DatabasePool` for concurrent read access while the tracking loop writes.
/// All public methods are safe to call from any actor/thread.
final class AppDatabase: Sendable {
    /// The underlying GRDB database pool.
    let pool: DatabasePool

    /// Opens (or creates) the database at the standard application support path.
    init() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("TimeSink", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dbURL = directoryURL.appendingPathComponent("timesink.db")

        var config = Configuration()
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }
        // In release builds, remove the trace:
        #if !DEBUG
        config = Configuration()
        #endif

        pool = try DatabasePool(path: dbURL.path, configuration: config)

        // Run migrations
        var migrator = DatabaseMigrator()
        #if DEBUG
        // In debug, always reset the migrator to re-run migrations if schema changes
        // migrator.eraseDatabaseOnSchemaChange = true
        #endif
        AppMigrations.registerMigrations(&migrator)
        try migrator.migrate(pool)
    }

    /// Opens a database at a custom path (for testing).
    init(path: String) throws {
        pool = try DatabasePool(path: path)
        var migrator = DatabaseMigrator()
        AppMigrations.registerMigrations(&migrator)
        try migrator.migrate(pool)
    }
}

// MARK: - Activity Record Operations

extension AppDatabase {

    /// Inserts a new activity record and returns its assigned row ID.
    @discardableResult
    func insertRecord(_ record: ActivityRecord) throws -> Int64 {
        try pool.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
            return mutableRecord.id ?? db.lastInsertedRowID
        }
    }

    /// Updates an existing activity record.
    func updateRecord(_ record: ActivityRecord) throws {
        guard let id = record.id else { return }

        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE activity_records
                    SET appName = ?,
                        windowTitle = ?,
                        detail = ?,
                        detailType = ?,
                        startedAt = ?,
                        endedAt = ?,
                        durationSeconds = ?,
                        isIdle = ?,
                        categoryId = ?,
                        categorizedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    record.appName,
                    record.windowTitle,
                    record.detail,
                    record.detailType.rawValue,
                    record.startedAt,
                    record.endedAt,
                    record.durationSeconds,
                    record.isIdle,
                    record.categoryId,
                    record.categorizedAt,
                    id,
                ]
            )
        }
    }

    /// Closes the current active record by setting its end time and duration.
    func closeRecord(id: Int64, endedAt: Date) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE activity_records
                    SET endedAt = ?,
                        durationSeconds = CAST((julianday(?) - julianday(startedAt)) * 86400 AS INTEGER)
                    WHERE id = ?
                    """,
                arguments: [endedAt, endedAt, id]
            )
        }
    }

    /// Fetches activity records for a given date range.
    func fetchRecords(from startDate: Date, to endDate: Date) throws -> [ActivityRecord] {
        try pool.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.startedAt >= startDate)
                .filter(ActivityRecord.Columns.startedAt < endDate)
                .order(ActivityRecord.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetches uncategorized, non-idle records for AI categorization.
    func fetchUncategorizedRecords(limit: Int = 200) throws -> [ActivityRecord] {
        try pool.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.categoryId == nil)
                .filter(ActivityRecord.Columns.isIdle == false)
                .filter(ActivityRecord.Columns.endedAt != nil)
                .order(ActivityRecord.Columns.startedAt.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Counts uncategorized, non-idle, ended records ready for AI categorization.
    func countUncategorizedRecords() throws -> Int {
        try pool.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.categoryId == nil)
                .filter(ActivityRecord.Columns.isIdle == false)
                .filter(ActivityRecord.Columns.endedAt != nil)
                .fetchCount(db)
        }
    }

    /// Assigns a category to activity records by their IDs.
    func assignCategory(categoryId: Int64, toRecordIds ids: [Int64]) throws {
        try pool.write { db in
            let now = Date()
            for id in ids {
                try db.execute(
                    sql: """
                        UPDATE activity_records
                        SET categoryId = ?, categorizedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [categoryId, now, id]
                )
            }
        }
    }

    /// Fetches the most recent activity record (the one currently active or last closed).
    func fetchMostRecentRecord() throws -> ActivityRecord? {
        try pool.read { db in
            try ActivityRecord
                .order(ActivityRecord.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }
}

// MARK: - Category Operations

extension AppDatabase {

    /// Fetches all categories ordered by sortOrder.
    func fetchAllCategories() throws -> [Category] {
        try pool.read { db in
            try Category
                .order(Category.Columns.sortOrder.asc)
                .fetchAll(db)
        }
    }

    /// Inserts or updates a category and returns its row ID.
    @discardableResult
    func saveCategory(_ category: Category) throws -> Int64 {
        try pool.write { db in
            if let id = category.id {
                try db.execute(
                    sql: """
                        UPDATE categories
                        SET name = ?,
                            description = ?,
                            color = ?,
                            isProductive = ?,
                            realm = ?,
                            sortOrder = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        category.name,
                        category.description,
                        category.color,
                        category.isProductive,
                        category.realm,
                        category.sortOrder,
                        id,
                    ]
                )
                return id
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO categories (name, description, color, isProductive, realm, sortOrder)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        category.name,
                        category.description,
                        category.color,
                        category.isProductive,
                        category.realm,
                        category.sortOrder,
                    ]
                )
                return db.lastInsertedRowID
            }
        }
    }

    /// Deletes a category by ID. Activity records referencing it get categoryId set to NULL.
    func deleteCategory(id: Int64) throws {
        try pool.write { db in
            _ = try Category.deleteOne(db, id: id)
        }
    }

    /// Updates the sort order for all categories.
    func reorderCategories(_ orderedIds: [Int64]) throws {
        try pool.write { db in
            for (index, id) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE categories SET sortOrder = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }
}

// MARK: - Categorization Log Operations

extension AppDatabase {

    /// Inserts a categorization log entry.
    func insertCategorizationLog(_ log: inout CategorizationLog) throws {
        try pool.write { db in
            try log.insert(db)
        }
    }

    /// Fetches the most recent categorization log entry.
    func fetchLastCategorizationLog() throws -> CategorizationLog? {
        try pool.read { db in
            try CategorizationLog
                .order(CategorizationLog.Columns.processedAt.desc)
                .fetchOne(db)
        }
    }
}

// MARK: - Aggregate Queries

extension AppDatabase {

    /// Summary of time per category for a date range.
    struct CategoryTimeSummary: Codable, FetchableRecord, Sendable {
        var categoryId: Int64?
        var categoryName: String?
        var categoryColor: String?
        var isProductive: Bool?
        var realm: String?
        var totalSeconds: Int
    }

    struct CategoryActivityCount: Codable, FetchableRecord, Sendable, Identifiable {
        var categoryId: Int64?
        var activityCount: Int

        var id: Int64 { categoryId ?? -1 }
    }

    struct CategoryAppSummary: Codable, FetchableRecord, Sendable, Identifiable {
        var appName: String
        var sessionCount: Int
        var totalSeconds: Int

        var id: String { appName }
    }

    struct CategoryDetailSummary: Codable, FetchableRecord, Sendable, Identifiable {
        var appName: String
        var detail: String
        var sessionCount: Int
        var totalSeconds: Int

        var id: String { appName + "::" + detail }

        var displayTitle: String {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(\(appName) activity)" : trimmed
        }
    }

    /// Fetches time grouped by category for the given date range.
    func fetchCategoryBreakdown(from startDate: Date, to endDate: Date, realm: String? = nil) throws -> [CategoryTimeSummary] {
        try pool.read { db in
            var sql = """
                SELECT
                    ar.categoryId,
                    c.name AS categoryName,
                    c.color AS categoryColor,
                    c.isProductive,
                    c.realm,
                    COALESCE(SUM(ar.durationSeconds), 0) AS totalSeconds
                FROM activity_records ar
                LEFT JOIN categories c ON ar.categoryId = c.id
                WHERE ar.startedAt >= ? AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                """
            var arguments: StatementArguments = [startDate, endDate]
            if let realm {
                sql += " AND c.realm = ?"
                arguments += [realm]
            }
            sql += " GROUP BY ar.categoryId ORDER BY totalSeconds DESC"
            return try CategoryTimeSummary.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetches activity counts grouped by category for the given date range.
    func fetchCategoryActivityCounts(from startDate: Date, to endDate: Date, realm: String? = nil) throws -> [CategoryActivityCount] {
        try pool.read { db in
            var sql = """
                SELECT
                    ar.categoryId,
                    COUNT(*) AS activityCount
                FROM activity_records ar
                LEFT JOIN categories c ON ar.categoryId = c.id
                WHERE ar.startedAt >= ?
                    AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                """
            var arguments: StatementArguments = [startDate, endDate]
            if let realm {
                sql += " AND c.realm = ?"
                arguments += [realm]
            }
            sql += " GROUP BY ar.categoryId"
            return try CategoryActivityCount.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetches app-level breakdown within a category for a date range.
    func fetchAppBreakdownForCategory(_ categoryId: Int64, from startDate: Date, to endDate: Date) throws -> [CategoryAppSummary] {
        try pool.read { db in
            let sql = """
                SELECT
                    appName,
                    COUNT(*) AS sessionCount,
                    COALESCE(SUM(durationSeconds), 0) AS totalSeconds
                FROM activity_records
                WHERE categoryId = ?
                    AND startedAt >= ?
                    AND startedAt < ?
                    AND isIdle = 0
                    AND endedAt IS NOT NULL
                GROUP BY appName
                ORDER BY totalSeconds DESC, sessionCount DESC
                """
            return try CategoryAppSummary.fetchAll(db, sql: sql, arguments: [categoryId, startDate, endDate])
        }
    }

    /// Fetches detail-level breakdown within a category for a date range.
    func fetchDetailBreakdownForCategory(_ categoryId: Int64, from startDate: Date, to endDate: Date) throws -> [CategoryDetailSummary] {
        try pool.read { db in
            let sql = """
                SELECT
                    appName,
                    COALESCE(detail, '') AS detail,
                    COUNT(*) AS sessionCount,
                    COALESCE(SUM(durationSeconds), 0) AS totalSeconds
                FROM activity_records
                WHERE categoryId = ?
                    AND startedAt >= ?
                    AND startedAt < ?
                    AND isIdle = 0
                    AND endedAt IS NOT NULL
                GROUP BY appName, COALESCE(detail, '')
                ORDER BY totalSeconds DESC, sessionCount DESC
                """
            return try CategoryDetailSummary.fetchAll(db, sql: sql, arguments: [categoryId, startDate, endDate])
        }
    }

    /// Summary of time per app for a date range.
    struct AppTimeSummary: Codable, FetchableRecord, Sendable {
        var appName: String
        var totalSeconds: Int
        var recordCount: Int
    }

    struct RealmBreakdown: Sendable {
        var workSeconds: Int
        var personalSeconds: Int
    }

    struct AppDetailSummary: Codable, FetchableRecord, Sendable, Identifiable {
        var detail: String
        var detailType: String?
        var totalSeconds: Int
        var sessionCount: Int

        var id: String { detail + "::" + (detailType ?? "") }
        var displayTitle: String {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Other / untitled" : trimmed
        }
    }

    /// Fetches time grouped by app for the given date range.
    func fetchAppBreakdown(from startDate: Date, to endDate: Date, realm: String? = nil) throws -> [AppTimeSummary] {
        try pool.read { db in
            var sql = """
                SELECT
                    ar.appName,
                    COALESCE(SUM(ar.durationSeconds), 0) AS totalSeconds,
                    COUNT(*) AS recordCount
                FROM activity_records ar
                LEFT JOIN categories c ON ar.categoryId = c.id
                WHERE ar.startedAt >= ? AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                """
            var arguments: StatementArguments = [startDate, endDate]
            if let realm {
                sql += " AND c.realm = ?"
                arguments += [realm]
            }
            sql += " GROUP BY ar.appName ORDER BY totalSeconds DESC"
            return try AppTimeSummary.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetches records for a specific app in a date range.
    func fetchRecordsForApp(_ appName: String, from startDate: Date, to endDate: Date) throws -> [ActivityRecord] {
        try pool.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.appName == appName)
                .filter(ActivityRecord.Columns.startedAt >= startDate)
                .filter(ActivityRecord.Columns.startedAt < endDate)
                .filter(ActivityRecord.Columns.isIdle == false)
                .order(ActivityRecord.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetches grouped detail breakdown for a specific app in a date range.
    func fetchDetailBreakdownForApp(_ appName: String, from startDate: Date, to endDate: Date, realm: String? = nil) throws -> [AppDetailSummary] {
        try pool.read { db in
            var sql = """
                SELECT
                    COALESCE(ar.detail, '') AS detail,
                    ar.detailType,
                    COALESCE(SUM(ar.durationSeconds), 0) AS totalSeconds,
                    COUNT(*) AS sessionCount
                FROM activity_records ar
                LEFT JOIN categories c ON ar.categoryId = c.id
                WHERE ar.appName = ?
                    AND ar.startedAt >= ?
                    AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                """
            var arguments: StatementArguments = [appName, startDate, endDate]
            if let realm {
                sql += " AND c.realm = ?"
                arguments += [realm]
            }
            sql += " GROUP BY COALESCE(ar.detail, ''), ar.detailType ORDER BY totalSeconds DESC, sessionCount DESC"
            return try AppDetailSummary.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Total tracked (non-idle) seconds for a date range.
    func fetchTotalTrackedSeconds(from startDate: Date, to endDate: Date, realm: String? = nil) throws -> Int {
        try pool.read { db in
            var sql = """
                SELECT COALESCE(SUM(durationSeconds), 0)
                FROM activity_records ar
                LEFT JOIN categories c ON ar.categoryId = c.id
                WHERE ar.startedAt >= ? AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                """
            var arguments: StatementArguments = [startDate, endDate]
            if let realm {
                sql += " AND c.realm = ?"
                arguments += [realm]
            }
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    func fetchRealmBreakdown(from startDate: Date, to endDate: Date) throws -> RealmBreakdown {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.realm, COALESCE(SUM(ar.durationSeconds), 0) AS totalSeconds
                FROM activity_records ar
                JOIN categories c ON ar.categoryId = c.id
                WHERE ar.startedAt >= ? AND ar.startedAt < ?
                    AND ar.isIdle = 0
                    AND ar.endedAt IS NOT NULL
                    AND c.realm IS NOT NULL
                GROUP BY c.realm
                """, arguments: [startDate, endDate])
            var workSeconds = 0
            var personalSeconds = 0
            for row in rows {
                let realm: String? = row["realm"]
                let seconds: Int = row["totalSeconds"]
                if realm == "work" { workSeconds = seconds }
                if realm == "personal" { personalSeconds = seconds }
            }
            return RealmBreakdown(workSeconds: workSeconds, personalSeconds: personalSeconds)
        }
    }

    /// Deletes records older than the given date.
    func deleteRecordsOlderThan(_ date: Date) throws -> Int {
        try pool.write { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.startedAt < date)
                .deleteAll(db)
        }
    }

    /// Deletes all data from all tables, resetting the database to a fresh state.
    /// Default categories are re-seeded after the wipe.
    func deleteAllData() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM categorization_log")
            try db.execute(sql: "DELETE FROM activity_records")
            try db.execute(sql: "DELETE FROM categories")

            // Re-seed default categories
            for defaultCategory in Category.defaults {
                var cat = defaultCategory
                try cat.insert(db)
            }
        }
    }

    /// Closes any records that were left open from a previous app run.
    /// This keeps the database consistent so only the current live record remains open.
    func closeAllOpenRecords(endedAt: Date = Date()) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE activity_records
                    SET endedAt = ?,
                        durationSeconds = CAST((julianday(?) - julianday(startedAt)) * 86400 AS INTEGER)
                    WHERE endedAt IS NULL
                    """,
                arguments: [endedAt, endedAt]
            )
        }
    }

    /// Closes any open records except the specified record ID.
    func closeAllOpenRecords(exceptID preservedID: Int64, endedAt: Date = Date()) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE activity_records
                    SET endedAt = ?,
                        durationSeconds = CAST((julianday(?) - julianday(startedAt)) * 86400 AS INTEGER)
                    WHERE endedAt IS NULL AND id != ?
                    """,
                arguments: [endedAt, endedAt, preservedID]
            )
        }
    }
}
