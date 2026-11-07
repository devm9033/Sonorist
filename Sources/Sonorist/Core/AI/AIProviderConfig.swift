import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini = "gemini"
    case groq = "groq"
    case openai = "openai"
    case ollama = "ollama"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini (Free)"
        case .groq: return "Groq - Llama 3.3 (Free)"
        case .openai: return "OpenAI ChatGPT"
        case .ollama: return "Local Ollama on Mac"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.0-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .openai: return "gpt-4o-mini"
        case .ollama: return "llama3"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/models"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        }
    }

    public var instructionsURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .groq: return "https://console.groq.com/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .ollama: return "https://ollama.com"
        }
    }
}

public final class AIProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = AIProviderConfig()

    private let defaults = UserDefaults.standard
    private let keyProvider = "Sonorist_AIProvider"
    private let keyApiKey = "Sonorist_AIApiKey"
    private let keyAutoDownload = "Sonorist_AIAutoDownload"
    private let keyDailyRefresh = "Sonorist_AIDailyRefresh"
    private let keyLastSync = "Sonorist_AILastSync"
    private let keyCustomEndpoint = "Sonorist_AICustomEndpoint"

    @Published public var selectedProvider: AIProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: keyProvider) }
    }

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: keyApiKey) }
    }

    @Published public var isAutoCurateOnDownloadEnabled: Bool {
        didSet { defaults.set(isAutoCurateOnDownloadEnabled, forKey: keyAutoDownload) }
    }

    @Published public var isDailyRefreshEnabled: Bool {
        didSet { defaults.set(isDailyRefreshEnabled, forKey: keyDailyRefresh) }
    }

    @Published public var customEndpoint: String {
        didSet { defaults.set(customEndpoint, forKey: keyCustomEndpoint) }
    }

    @Published public var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate?.timeIntervalSince1970, forKey: keyLastSync) }
    }

    public var isConfigured: Bool {
        if selectedProvider == .ollama { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        let provStr = defaults.string(forKey: keyProvider) ?? AIProvider.gemini.rawValue
        self.selectedProvider = AIProvider(rawValue: provStr) ?? .gemini
        self.apiKey = defaults.string(forKey: keyApiKey) ?? ""
        self.isAutoCurateOnDownloadEnabled = defaults.object(forKey: keyAutoDownload) as? Bool ?? true
        self.isDailyRefreshEnabled = defaults.object(forKey: keyDailyRefresh) as? Bool ?? true
        self.customEndpoint = defaults.string(forKey: keyCustomEndpoint) ?? ""

        if let time = defaults.object(forKey: keyLastSync) as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: time)
        } else {
            self.lastSyncDate = nil
        }
    }
}
