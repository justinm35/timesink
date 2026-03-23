import Foundation

/// Handles batch AI categorization of activity records using the Claude API.
///
/// Runs periodically (every 30 minutes by default) or on manual trigger.
/// Uses claude-haiku-4-5-20251001 for fast, cheap categorization.
actor CategorizationEngine {

    private let database: AppDatabase

    /// The maximum number of records to categorize in a single batch.
    private let maxBatchSize = 100

    /// Whether a categorization is currently in progress.
    private(set) var isRunning = false

    /// Error from the last categorization attempt, if any.
    private(set) var lastError: String?

    /// Timestamp of the last successful categorization.
    private(set) var lastSuccessfulRun: Date?

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Categorize

    /// Runs a categorization batch on all uncategorized, non-idle records.
    ///
    /// - Returns: The number of records categorized.
    @discardableResult
    func categorizeBatch() async throws -> Int {
        guard !isRunning else { return 0 }
        isRunning = true
        lastError = nil

        defer { isRunning = false }

        let provider = currentProvider()

        // 1. Get the API key
        guard let apiKey = KeychainHelper.apiKey(for: provider), !apiKey.isEmpty else {
            lastError = "No \(provider.displayName) API key configured. Add one in onboarding or Settings."
            throw CategorizationError.noAPIKey
        }

        // 2. Fetch uncategorized records
        let records = try database.fetchUncategorizedRecords(limit: maxBatchSize)
        guard !records.isEmpty else { return 0 }

        // 3. Fetch categories
        let categories = try database.fetchAllCategories()
        guard !categories.isEmpty else {
            lastError = "No categories defined."
            throw CategorizationError.noCategories
        }

        // 4. Build prompt
        let (systemPrompt, userMessage) = Prompts.buildCategorizationPrompt(
            records: records,
            categories: categories
        )

        // 5. Call Claude API
        let response = try await callProvider(
            provider: provider,
            system: systemPrompt,
            user: userMessage,
            apiKey: apiKey
        )

        // 6. Parse response
        let assignments = try parseAssignments(response.content, validCategoryIds: Set(categories.compactMap(\.id)))

        // 7. Update records
        for assignment in assignments {
            try database.assignCategory(
                categoryId: assignment.categoryId,
                toRecordIds: [assignment.recordId]
            )
        }

        // 8. Log the categorization
        var log = CategorizationLog(
            batchSize: assignments.count,
            processedAt: Date(),
            modelUsed: provider.model,
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens
        )
        try database.insertCategorizationLog(&log)

        lastSuccessfulRun = Date()
        return assignments.count
    }

    // MARK: - Claude API

    private struct ProviderResponse: Sendable {
        let content: String
        let promptTokens: Int
        let completionTokens: Int
    }

    private func currentProvider() -> AIProvider {
        let raw = UserDefaults.standard.string(forKey: "selectedAIProvider") ?? AIProvider.anthropic.rawValue
        return AIProvider(rawValue: raw) ?? .anthropic
    }

    private func callProvider(provider: AIProvider, system: String, user: String, apiKey: String) async throws -> ProviderResponse {
        switch provider {
        case .anthropic:
            return try await callAnthropic(system: system, user: user, apiKey: apiKey, provider: provider)
        case .openai:
            return try await callOpenAI(system: system, user: user, apiKey: apiKey, provider: provider)
        case .gemini:
            return try await callGemini(system: system, user: user, apiKey: apiKey, provider: provider)
        }
    }

    private func callAnthropic(system: String, user: String, apiKey: String, provider: AIProvider) async throws -> ProviderResponse {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": provider.model,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw CategorizationError.invalidResponse
        }

        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown error"
            lastError = "\(provider.displayName) API error (\(response.statusCode)): \(errorBody)"
            throw CategorizationError.apiError(statusCode: response.statusCode, body: errorBody)
        }

        // Parse the response JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw CategorizationError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let promptTokens = usage?["input_tokens"] as? Int ?? 0
        let completionTokens = usage?["output_tokens"] as? Int ?? 0

        return ProviderResponse(
            content: text,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    private func callOpenAI(system: String, user: String, apiKey: String, provider: AIProvider) async throws -> ProviderResponse {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": provider.model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        guard let response = httpResponse as? HTTPURLResponse else { throw CategorizationError.invalidResponse }
        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown error"
            lastError = "\(provider.displayName) API error (\(response.statusCode)): \(errorBody)"
            throw CategorizationError.apiError(statusCode: response.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw CategorizationError.invalidResponse }

        let usage = json["usage"] as? [String: Any]
        return ProviderResponse(
            content: text,
            promptTokens: usage?["prompt_tokens"] as? Int ?? 0,
            completionTokens: usage?["completion_tokens"] as? Int ?? 0
        )
    }

    private func callGemini(system: String, user: String, apiKey: String, provider: AIProvider) async throws -> ProviderResponse {
        var components = URLComponents(url: provider.apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw CategorizationError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": user]]]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        guard let response = httpResponse as? HTTPURLResponse else { throw CategorizationError.invalidResponse }
        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown error"
            lastError = "\(provider.displayName) API error (\(response.statusCode)): \(errorBody)"
            throw CategorizationError.apiError(statusCode: response.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else { throw CategorizationError.invalidResponse }

        let usage = json["usageMetadata"] as? [String: Any]
        return ProviderResponse(
            content: text,
            promptTokens: usage?["promptTokenCount"] as? Int ?? 0,
            completionTokens: usage?["candidatesTokenCount"] as? Int ?? 0
        )
    }

    // MARK: - Response Parsing

    private struct Assignment {
        let recordId: Int64
        let categoryId: Int64
    }

    private func parseAssignments(_ text: String, validCategoryIds: Set<Int64>) throws -> [Assignment] {
        // The response should be a JSON array like: [{"id": 1, "category_id": 2}, ...]
        // Strip any markdown code fences if present
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            // Remove code fences
            let lines = jsonText.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.hasPrefix("```") }
            jsonText = filtered.joined(separator: "\n")
        }

        guard let data = jsonText.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            lastError = "Failed to parse AI response as JSON array"
            throw CategorizationError.parseError(text)
        }

        var assignments: [Assignment] = []

        for item in array {
            guard let recordId = (item["id"] as? NSNumber)?.int64Value,
                  let categoryId = (item["category_id"] as? NSNumber)?.int64Value,
                  validCategoryIds.contains(categoryId)
            else {
                continue // Skip invalid entries
            }

            assignments.append(Assignment(recordId: recordId, categoryId: categoryId))
        }

        return assignments
    }
}

// MARK: - CategorizationError

enum CategorizationError: LocalizedError, Sendable {
    case noAPIKey
    case noCategories
    case apiError(statusCode: Int, body: String)
    case invalidResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured"
        case .noCategories:
            return "No categories defined for categorization"
        case .apiError(let code, let body):
            return "Claude API error (\(code)): \(body)"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .parseError(let text):
            return "Failed to parse categorization response: \(text.prefix(200))"
        }
    }
}
