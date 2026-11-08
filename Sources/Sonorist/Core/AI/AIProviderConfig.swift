import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openrouter = "openrouter"
    case gemini = "gemini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openrouter: return "OpenRouter (Recommended Free Key)"
        case .gemini: return "Google Gemini"
        }
    }

    public var shortName: String {
        switch self {
        case .openrouter: return "OpenRouter"
        case .gemini: return "Google Gemini"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openrouter: return "openrouter/free"
        case .gemini: return "gemini-3.8-flash"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }

    public var instructionsURL: String {
        switch self {
        case .openrouter: return "https://openrouter.ai/keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        }
    }

    public var requiresApiKey: Bool {
        return true
    }
}

public final class AIProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = AIProviderConfig()

    private let defaults = UserDefaults.standard
    private let keyProvider = "Sonorist_AIProvider"
    private let keyApiKey = "Sonorist_AIApiKey"
    private let keyAutoDownload = "Sonorist_AIAutoDownload"
    private let keyAutoRetryPending = "Sonorist_AIAutoRetryPending"
    private let keyLastSync = "Sonorist_AILastSync"
    private let keyCustomEndpoint = "Sonorist_AICustomEndpoint"
    private let keyGeminiModel = "Sonorist_AIGeminiModel"

    @Published public var selectedProvider: AIProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: keyProvider) }
    }

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: keyApiKey) }
    }

    @Published public var isAutoCurateOnDownloadEnabled: Bool {
        didSet { defaults.set(isAutoCurateOnDownloadEnabled, forKey: keyAutoDownload) }
    }

    @Published public var isAutoRetryPendingEnabled: Bool {
        didSet { defaults.set(isAutoRetryPendingEnabled, forKey: keyAutoRetryPending) }
    }

    public var isDailyRefreshEnabled: Bool {
        get { isAutoRetryPendingEnabled }
        set { isAutoRetryPendingEnabled = newValue }
    }

    @Published public var customEndpoint: String {
        didSet { defaults.set(customEndpoint, forKey: keyCustomEndpoint) }
    }

    @Published public var activeGeminiModel: String {
        didSet { defaults.set(activeGeminiModel, forKey: keyGeminiModel) }
    }

    @Published public var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate?.timeIntervalSince1970, forKey: keyLastSync) }
    }

    public var isConfigured: Bool {
        if !selectedProvider.requiresApiKey { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        let provStr = defaults.string(forKey: keyProvider) ?? AIProvider.openrouter.rawValue
        self.selectedProvider = AIProvider(rawValue: provStr) ?? .openrouter
        self.apiKey = defaults.string(forKey: keyApiKey) ?? ""
        self.isAutoCurateOnDownloadEnabled = defaults.object(forKey: keyAutoDownload) as? Bool ?? true
        self.isAutoRetryPendingEnabled = defaults.object(forKey: keyAutoRetryPending) as? Bool ?? true
        self.customEndpoint = defaults.string(forKey: keyCustomEndpoint) ?? ""
        let savedModel = defaults.string(forKey: keyGeminiModel) ?? "gemini-3.8-flash"
        if savedModel.contains("1.5") || savedModel.contains("2.0") || savedModel.contains("2.5") {
            self.activeGeminiModel = "gemini-3.8-flash"
        } else {
            self.activeGeminiModel = savedModel
        }

        if let time = defaults.object(forKey: keyLastSync) as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: time)
        } else {
            self.lastSyncDate = nil
        }
    }
}
