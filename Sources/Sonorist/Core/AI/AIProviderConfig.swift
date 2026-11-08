import Foundation

public struct OpenRouterModel: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let contextLength: Int?

    public init(id: String, name: String, description: String? = nil, contextLength: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.contextLength = contextLength
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
    }
}

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openrouter = "openrouter"

    public var id: String { rawValue }

    public var displayName: String { "OpenRouter (Free Key)" }
    public var shortName: String { "OpenRouter" }
    public var defaultModel: String { "meta-llama/llama-3.3-70b-instruct:free" }
    public var defaultEndpoint: String { "https://openrouter.ai/api/v1/chat/completions" }
    public var modelsEndpoint: String { "https://openrouter.ai/api/v1/models" }
    public var instructionsURL: String { "https://openrouter.ai/keys" }
    public var requiresApiKey: Bool { true }
}

public final class AIProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = AIProviderConfig()

    private let defaults = UserDefaults.standard
    private let keyProvider = "Sonorist_AIProvider"
    private let keyApiKey = "Sonorist_AIApiKey"
    private let keyAutoDownload = "Sonorist_AIAutoDownload"
    private let keyAutoRetryPending = "Sonorist_AIAutoRetryPending"
    private let keyLastSync = "Sonorist_AILastSync"
    private let keyOpenRouterModel = "Sonorist_OpenRouterModel"
    private let keyDiscoveredModels = "Sonorist_DiscoveredFreeModels"

    public static let fallbackFreeModels: [OpenRouterModel] = [
        OpenRouterModel(id: "meta-llama/llama-3.3-70b-instruct:free", name: "Meta: Llama 3.3 70B Instruct (free)", description: "High-intelligence reasoning for song classification"),
        OpenRouterModel(id: "deepseek/deepseek-r1:free", name: "DeepSeek: R1 (free)", description: "Advanced reasoning model"),
        OpenRouterModel(id: "qwen/qwen-2.5-72b-instruct:free", name: "Qwen 2.5 72B Instruct (free)", description: "Strong multilingual Asian language comprehension"),
        OpenRouterModel(id: "mistralai/mistral-small-24b-instruct-2501:free", name: "Mistral Small 24B (free)", description: "Fast, accurate and lightweight"),
        OpenRouterModel(id: "google/gemini-2.0-flash-lite:free", name: "Google: Gemini 2.0 Flash Lite (free)", description: "Low-latency Flash model"),
        OpenRouterModel(id: "openrouter/free", name: "OpenRouter Free Auto-Router", description: "Dynamically routes to whichever free model is available")
    ]

    @Published public var selectedProvider: AIProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: keyProvider) }
    }

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: keyApiKey) }
    }

    @Published public var selectedModelId: String {
        didSet { defaults.set(selectedModelId, forKey: keyOpenRouterModel) }
    }

    @Published public var availableFreeModels: [OpenRouterModel] {
        didSet {
            if let data = try? JSONEncoder().encode(availableFreeModels) {
                defaults.set(data, forKey: keyDiscoveredModels)
            }
        }
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

    @Published public var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate?.timeIntervalSince1970, forKey: keyLastSync) }
    }

    public var isConfigured: Bool {
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.selectedProvider = .openrouter
        self.apiKey = defaults.string(forKey: keyApiKey) ?? ""
        self.isAutoCurateOnDownloadEnabled = defaults.object(forKey: keyAutoDownload) as? Bool ?? true
        self.isAutoRetryPendingEnabled = defaults.object(forKey: keyAutoRetryPending) as? Bool ?? true

        let savedModel = defaults.string(forKey: keyOpenRouterModel) ?? "meta-llama/llama-3.3-70b-instruct:free"
        if savedModel.contains("gemini-2.0-flash-exp") {
            self.selectedModelId = "meta-llama/llama-3.3-70b-instruct:free"
        } else {
            self.selectedModelId = savedModel
        }

        if let savedData = defaults.data(forKey: keyDiscoveredModels),
           let decoded = try? JSONDecoder().decode([OpenRouterModel].self, from: savedData),
           !decoded.isEmpty {
            self.availableFreeModels = decoded
        } else {
            self.availableFreeModels = Self.fallbackFreeModels
        }

        if let time = defaults.object(forKey: keyLastSync) as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: time)
        } else {
            self.lastSyncDate = nil
        }
    }
}
