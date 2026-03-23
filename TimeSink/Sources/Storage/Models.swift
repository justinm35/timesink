import Foundation
import GRDB

// MARK: - DetailType

/// The type of detail captured for an activity record.
enum DetailType: String, Codable, Sendable, DatabaseValueConvertible {
    case url = "url"
    case terminalPane = "terminal_pane"
    case app = "app"
}

// MARK: - ActivityRecord

/// A single tracked activity period — one app/detail combination from start to end.
struct ActivityRecord: Codable, Sendable, Identifiable {
    var id: Int64?
    var appName: String
    var windowTitle: String
    var detail: String?
    var detailType: DetailType
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var isIdle: Bool
    var categoryId: Int64?
    var categorizedAt: Date?
}

extension ActivityRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_records"

    static let category = belongsTo(Category.self, using: ForeignKey(["categoryId"]))
    var category: QueryInterfaceRequest<Category> {
        request(for: ActivityRecord.category)
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appName = Column(CodingKeys.appName)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let detail = Column(CodingKeys.detail)
        static let detailType = Column(CodingKeys.detailType)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let isIdle = Column(CodingKeys.isIdle)
        static let categoryId = Column(CodingKeys.categoryId)
        static let categorizedAt = Column(CodingKeys.categorizedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Category

/// A user-defined category for grouping activities.
struct Category: Codable, Sendable, Identifiable {
    var id: Int64?
    var name: String
    var description: String
    var color: String
    var isProductive: Bool
    var realm: String?
    var sortOrder: Int
}

extension Category: FetchableRecord, PersistableRecord {
    static let databaseTableName = "categories"

    static let activityRecords = hasMany(ActivityRecord.self)
    var activityRecords: QueryInterfaceRequest<ActivityRecord> {
        request(for: Category.activityRecords)
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let description = Column(CodingKeys.description)
        static let color = Column(CodingKeys.color)
        static let isProductive = Column(CodingKeys.isProductive)
        static let realm = Column(CodingKeys.realm)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Default Categories

extension Category {
    /// The default categories seeded on first launch.
    static let defaults: [Category] = [
        Category(name: "Deep Work", description: "Time spent writing code, debugging, or reading documentation directly related to building software", color: "#4A90D9", isProductive: true, realm: nil, sortOrder: 0),
        Category(name: "Communication", description: "Slack, email, messaging, video calls, and any form of team communication", color: "#F5A623", isProductive: true, realm: nil, sortOrder: 1),
        Category(name: "Research", description: "Reading articles, documentation, Stack Overflow, technical blogs, or exploring new tools and libraries", color: "#7B68EE", isProductive: true, realm: nil, sortOrder: 2),
        Category(name: "Code Review", description: "Reviewing pull requests, reading diffs, leaving review comments on GitHub or similar platforms", color: "#50C878", isProductive: true, realm: nil, sortOrder: 3),
        Category(name: "DevOps", description: "CI/CD, deployment, infrastructure, monitoring dashboards, server management, Docker, Kubernetes", color: "#FF6B6B", isProductive: true, realm: nil, sortOrder: 4),
        Category(name: "Admin", description: "Project management, Jira/Linear tickets, planning, meetings scheduling, time tracking, HR tools", color: "#95A5A6", isProductive: true, realm: nil, sortOrder: 5),
        Category(name: "Browsing", description: "General web browsing, social media, news, Reddit, YouTube, or other non-work-related websites", color: "#E67E22", isProductive: false, realm: nil, sortOrder: 6),
        Category(name: "Entertainment", description: "Music, video streaming, games, or other entertainment activities on the computer", color: "#E74C3C", isProductive: false, realm: nil, sortOrder: 7),
    ]
}

// MARK: - CategorizationLog

/// Audit trail for AI categorization batches.
struct CategorizationLog: Codable, Sendable, Identifiable {
    var id: Int64?
    var batchSize: Int
    var processedAt: Date
    var modelUsed: String
    var promptTokens: Int
    var completionTokens: Int
}

extension CategorizationLog: FetchableRecord, PersistableRecord {
    static let databaseTableName = "categorization_log"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let batchSize = Column(CodingKeys.batchSize)
        static let processedAt = Column(CodingKeys.processedAt)
        static let modelUsed = Column(CodingKeys.modelUsed)
        static let promptTokens = Column(CodingKeys.promptTokens)
        static let completionTokens = Column(CodingKeys.completionTokens)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
