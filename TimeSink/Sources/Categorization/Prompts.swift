import Foundation

/// Builds prompts for Claude API categorization requests.
enum Prompts {

    /// Builds the categorization prompt for a batch of activity records.
    ///
    /// - Parameters:
    ///   - records: The uncategorized activity records.
    ///   - categories: The available categories to assign.
    /// - Returns: The system prompt and user message for the API call.
    static func buildCategorizationPrompt(
        records: [ActivityRecord],
        categories: [Category]
    ) -> (system: String, user: String) {
        let system = """
            You are a time-tracking categorization assistant. Your job is to assign \
            each computer activity to the most appropriate category based on the app name, \
            window title, and any additional detail provided.

            Respond with ONLY a JSON array. No explanation, no markdown, no code fences. \
            Just the raw JSON array.

            Format: [{"id": <record_id>, "category_id": <category_id>}]

            If you are unsure about a categorization, pick the closest match. \
            Every activity must be assigned a category.
            """

        var userMessage = "Here are the available categories:\n\n"

        for category in categories {
            userMessage += "- ID \(category.id ?? 0): \"\(category.name)\" — \(category.description)\n"
        }

        userMessage += "\nCategorize each activity below:\n\n"

        for record in records {
            let detail = record.detail.map { sanitizePath($0) } ?? "none"
            userMessage += "- id:\(record.id ?? 0) app:\"\(record.appName)\" "
            userMessage += "title:\"\(record.windowTitle)\" "
            userMessage += "detail:\"\(detail)\" "
            userMessage += "type:\(record.detailType.rawValue)\n"
        }

        return (system: system, user: userMessage)
    }

    /// Strips the user's home directory from paths for privacy.
    private static func sanitizePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }
}
