import Foundation

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openai
    case gemini

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "GPT"
        case .gemini: return "Gemini"
        }
    }

    var iconName: String {
        switch self {
        case .anthropic: return "brain"
        case .openai: return "sparkles"
        case .gemini: return "globe.americas"
        }
    }

    var model: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        }
    }

    var apiURL: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        }
    }

    var consoleURL: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/")!
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: return KeychainHelper.anthropicAPIKeyKey
        case .openai: return KeychainHelper.openAIAPIKeyKey
        case .gemini: return KeychainHelper.geminiAPIKeyKey
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    var providerAccentHex: String {
        switch self {
        case .anthropic: return "#4A90D9"
        case .openai: return "#50C878"
        case .gemini: return "#F5A623"
        }
    }

    var providerAccentName: String { providerAccentHex }
}
