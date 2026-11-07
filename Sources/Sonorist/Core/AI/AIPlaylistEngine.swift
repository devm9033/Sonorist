import Foundation
import Combine
import Network

public final class AIPlaylistEngine: ObservableObject, @unchecked Sendable {
    public static let shared = AIPlaylistEngine()

    private let config = AIProviderConfig.shared
    private let cacheManager = MediaCacheManager.shared
    private let queue = DispatchQueue(label: "com.sonorist.ai.playlist.queue", qos: .userInitiated)
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sonorist.ai.networkMonitor", qos: .utility)

    @Published public var curatedLibrary: AICuratedLibrary = AICuratedLibrary()
    @Published public var pendingQueue: [Track] = []
    @Published public var isCurating: Bool = false
    @Published public var isProcessingPendingQueue: Bool = false
    @Published public var lastSyncError: String?
    @Published public var showingSettingsSheet: Bool = false
    @Published public var spinRefresh: Bool = false
    @Published public var testingConnection: Bool = false
    @Published public var connectionMessage: String?

    private var storageURL: URL {
        cacheManager.parentDirectory.appendingPathComponent("AICuratedPlaylists.json")
    }

    public var pendingQueueURL: URL {
        cacheManager.parentDirectory.appendingPathComponent("pending_curation_queue.json")
    }

    private init() {
        loadCachedLibrary()
        loadPendingQueue()
        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                Task {
                    await self.processPendingQueueIfNeeded()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Persistence

    public func loadCachedLibrary() {
        var loaded: AICuratedLibrary?
        queue.sync {
            guard FileManager.default.fileExists(atPath: storageURL.path),
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder().decode(AICuratedLibrary.self, from: data) else {
                return
            }
            loaded = decoded
        }
        if let loaded = loaded {
            self.curatedLibrary = loaded
            reconcileWithCachedTracks()
        }
    }

    /// Prunes orphaned track IDs that no longer exist in the local offline media cache.
    public func reconcileWithCachedTracks() {
        let cachedTracks = cacheManager.getAllCachedTracks()
        let cachedIds = Set(cachedTracks.map { $0.id })

        var pendingChanged = false
        let origPendingCount = pendingQueue.count
        pendingQueue.removeAll(where: { !cachedIds.contains($0.id) })
        if pendingQueue.count != origPendingCount {
            savePendingQueue()
        }

        var libraryChanged = false
        for lIdx in (0..<curatedLibrary.categories.count).reversed() {
            for gIdx in (0..<curatedLibrary.categories[lIdx].genres.count).reversed() {
                let prev = curatedLibrary.categories[lIdx].genres[gIdx].trackIds.count
                curatedLibrary.categories[lIdx].genres[gIdx].trackIds.removeAll(where: { !cachedIds.contains($0) })
                if curatedLibrary.categories[lIdx].genres[gIdx].trackIds.count != prev {
                    libraryChanged = true
                }
            }
            curatedLibrary.categories[lIdx].genres.removeAll(where: { $0.trackIds.isEmpty })
        }
        curatedLibrary.categories.removeAll(where: { $0.genres.isEmpty })
        if libraryChanged {
            saveLibrary()
        }
    }

    public func saveLibrary(sync: Bool = false) {
        let lib = self.curatedLibrary
        let fileURL = self.storageURL
        let work = {
            do {
                let data = try JSONEncoder().encode(lib)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] Failed to save curated library: \(error)")
                #endif
            }
        }
        if sync {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    public func loadPendingQueue() {
        var loaded: [Track]?
        queue.sync {
            guard FileManager.default.fileExists(atPath: pendingQueueURL.path),
                  let data = try? Data(contentsOf: pendingQueueURL),
                  let decoded = try? JSONDecoder().decode([Track].self, from: data) else {
                return
            }
            loaded = decoded
        }
        if let loaded = loaded {
            self.pendingQueue = loaded
        }
    }

    public func savePendingQueue(sync: Bool = false) {
        let items = self.pendingQueue
        let fileURL = self.pendingQueueURL
        let work = {
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] Failed to save pending queue: \(error)")
                #endif
            }
        }
        if sync {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    // MARK: - Full Library Curation

    /// Analyzes all downloaded tracks in the local cache and organizes them into Language and Genre folders.
    public func curateEntireLibrary(force: Bool = false) async {
        let cachedTracks = cacheManager.getAllCachedTracks()
        guard !cachedTracks.isEmpty else {
            Task { @MainActor in
                self.curatedLibrary = AICuratedLibrary(lastUpdated: Date(), categories: [])
                self.saveLibrary()
            }
            return
        }

        Task { @MainActor in
            self.isCurating = true
            self.lastSyncError = nil
        }

        defer {
            Task { @MainActor in
                self.isCurating = false
            }
        }

        // 1. If an AI API Key is configured, attempt intelligent LLM curation
        if config.isConfigured {
            do {
                let result = try await queryAICuration(for: cachedTracks)
                Task { @MainActor in
                    self.curatedLibrary = result
                    self.config.lastSyncDate = Date()
                    self.saveLibrary()
                }
                return
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] AI API call failed, falling back to local heuristic: \(error)")
                #endif
                Task { @MainActor in
                    self.lastSyncError = error.localizedDescription
                }
            }
        }

        // 2. Local Apple-native heuristic clustering (Zero-Network fallback)
        let heuristicResult = performHeuristicClustering(for: cachedTracks)
        Task { @MainActor in
            self.curatedLibrary = heuristicResult
            self.config.lastSyncDate = Date()
            self.saveLibrary()
        }
    }

    // MARK: - Instant Download Hook & Outbox Event Architecture

    /// Called silently immediately upon track download completion.
    /// Uses the active internet connection to classify with the API immediately.
    /// If the API call fails or is unconfigured, logs the track to the outbox queue (`pending_curation_queue.json`)
    /// and uses local heuristics so the user immediately sees the track organized without delay.
    public func categorizeNewTrack(_ track: Track) async {
        guard config.isAutoCurateOnDownloadEnabled else { return }

        // 1. If API is configured, attempt fast single-track classification
        if config.isConfigured {
            do {
                let classification = try await querySingleTrackClassification(track: track)
                Task { @MainActor in
                    self.curatedLibrary.insert(
                        trackId: track.id,
                        language: classification.language,
                        genreName: classification.genre,
                        genreIcon: classification.icon,
                        genreDescription: classification.description
                    )
                    // Successfully classified by API: remove from pending queue if present
                    self.pendingQueue.removeAll(where: { $0.id == track.id })
                    self.saveLibrary()
                    self.savePendingQueue()
                }
                return
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] Instant classification failed (\(error.localizedDescription)). Logging to pending queue.")
                #endif
                Task { @MainActor in
                    self.lastSyncError = error.localizedDescription
                }
            }
        }

        // 2. Fallback / Offline / API Unavailable:
        // A) Record track in persistent pending outbox queue file
        Task { @MainActor in
            if !self.pendingQueue.contains(where: { $0.id == track.id }) {
                self.pendingQueue.append(track)
                self.savePendingQueue()
            }

            // B) Apply immediate zero-latency local heuristic classification
            let fallback = self.classifyTrackHeuristically(track)
            self.curatedLibrary.insert(
                trackId: track.id,
                language: fallback.language,
                genreName: fallback.genre,
                genreIcon: fallback.icon,
                genreDescription: fallback.description
            )
            self.saveLibrary()
        }
    }

    /// Removes track when un-downloaded from offline library
    public func handleTrackRemoved(videoId: String) {
        let work = {
            self.curatedLibrary.remove(trackId: videoId)
            self.pendingQueue.removeAll(where: { $0.id == videoId })
            self.saveLibrary()
            self.savePendingQueue()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Event-Driven Outbox Queue Processing

    /// Scans the persistent pending outbox queue log file (`pending_curation_queue.json`).
    /// If the queue is empty, makes ZERO network requests!
    /// If there are pending tracks, synchronizes them with the API and clears them from the log.
    public func processPendingQueueIfNeeded() async {
        guard config.isConfigured else { return }

        let pending = await MainActor.run { self.pendingQueue }
        guard !pending.isEmpty else {
            // Outbox queue log is clean! Zero network calls required.
            return
        }

        await MainActor.run {
            self.isProcessingPendingQueue = true
        }

        defer {
            Task { @MainActor in
                self.isProcessingPendingQueue = false
            }
        }

        var successfullySynced = [String: AISongClassification]()

        for track in pending {
            do {
                let classification = try await querySingleTrackClassification(track: track)
                successfullySynced[track.id] = classification
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] Failed to sync pending track \(track.title): \(error.localizedDescription)")
                #endif
                // Mid-batch network failure: halt iteration and keep remaining tracks in outbox log
                break
            }
        }

        if !successfullySynced.isEmpty {
            await MainActor.run {
                for (trackId, classification) in successfullySynced {
                    // Remove previous heuristic placement if any
                    self.curatedLibrary.remove(trackId: trackId)
                    // Insert verified AI classification
                    self.curatedLibrary.insert(
                        trackId: trackId,
                        language: classification.language,
                        genreName: classification.genre,
                        genreIcon: classification.icon,
                        genreDescription: classification.description
                    )
                }
                self.pendingQueue.removeAll(where: { successfullySynced.keys.contains($0.id) })
                self.savePendingQueue()
                self.saveLibrary()
            }
        }
    }

    // MARK: - API Key Connection Verification

    /// Discovers active supported Gemini model for the user's API key
    public func discoverGeminiModel(apiKey: String) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10.0
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return nil
        }

        let validModels = models.compactMap { m -> String? in
            guard let name = m["name"] as? String,
                  let methods = m["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else {
                return nil
            }
            return name.replacingOccurrences(of: "models/", with: "")
        }

        let preferences = [
            "gemini-3.8-flash",
            "gemini-3.5-flash",
            "gemini-3.0-flash",
            "gemini-2.5-flash",
            "gemini-2.0-flash"
        ]

        for pref in preferences {
            if validModels.contains(pref) {
                return pref
            }
        }

        if let anyFlash = validModels.first(where: { $0.contains("flash") }) {
            return anyFlash
        }
        return validModels.first
    }

    /// Tests the connection to the configured AI API with a quick ping.
    /// Returns a user-friendly status message and sets connectionMessage.
    @MainActor
    public func testAPIConnection() async -> (success: Bool, message: String) {
        guard config.isConfigured else {
            let msg = "Please enter an API key first."
            self.connectionMessage = msg
            return (false, msg)
        }

        self.testingConnection = true
        self.connectionMessage = nil
        defer { self.testingConnection = false }

        let provider = config.selectedProvider

        do {
            let testPrompt = "Respond strictly with valid JSON: {\"status\": \"ok\"}"
            _ = try await executeLLMRequest(prompt: testPrompt)
            let currentModel = (provider == .gemini) ? config.activeGeminiModel : provider.defaultModel
            let successMsg = "✓ Connection Verified! \(provider.displayName) (\(currentModel)) is ready."
            self.connectionMessage = successMsg
            self.lastSyncError = nil

            // If there were pending tracks waiting in the outbox, process them automatically!
            Task {
                await self.processPendingQueueIfNeeded()
            }
            return (true, successMsg)
        } catch {
            let nsErr = error as NSError
            let detail = nsErr.localizedDescription
            let errMsg: String
            if nsErr.code == 400 || nsErr.code == 401 || nsErr.code == 403 {
                errMsg = "✗ Authentication Failed (\(nsErr.code)): \(detail)"
            } else if (error as? URLError)?.code == .notConnectedToInternet {
                errMsg = "✗ Network Offline: Could not reach \(provider.displayName). Check your internet connection."
            } else {
                errMsg = "✗ Connection Failed: \(detail)"
            }
            self.connectionMessage = errMsg
            self.lastSyncError = errMsg
            return (false, errMsg)
        }
    }

    /// Backward compatibility alias
    public func performDailySyncIfNeeded() async {
        await processPendingQueueIfNeeded()
    }

    // MARK: - LLM API Integration

    public struct AISongClassification: Codable, Sendable {
        public let language: String
        public let genre: String
        public let icon: String
        public let description: String

        public init(language: String, genre: String, icon: String, description: String) {
            self.language = language
            self.genre = genre
            self.icon = icon
            self.description = description
        }
    }

    private func querySingleTrackClassification(track: Track) async throws -> AISongClassification {
        let prompt = """
        Classify this song for an offline music player into a primary Language (e.g. Hindi, English, Punjabi, Instrumental) and one of these 5 standard genres:
        1. Pop & Dance
        2. Melodic & Romance
        3. Acoustic & Chill
        4. Classics & Heritage
        5. Energetic & Rap

        Song Title: "\(track.title)"
        Artist: "\(track.artist)"

        Respond strictly in valid JSON matching this schema:
        {
          "language": "LanguageName",
          "genre": "GenreName",
          "icon": "music.note",
          "description": "Short 1-line description"
        }
        """

        let rawResponse = try await executeLLMRequest(prompt: prompt)
        return try parseJSON(AISongClassification.self, from: rawResponse)
    }

    private func queryAICuration(for tracks: [Track]) async throws -> AICuratedLibrary {
        let trackPayload = tracks.map { ["id": $0.id, "title": $0.title, "artist": $0.artist] }
        let payloadData = try JSONSerialization.data(withJSONObject: trackPayload)
        let jsonStr = String(data: payloadData, encoding: .utf8) ?? "[]"

        let prompt = """
        You are an expert music curator. Given this list of offline songs, organize them into a clean folder hierarchy:
        1. Primary Language (e.g. Hindi, English, Punjabi, Instrumental, Korean, Spanish).
        2. Within each language, strictly limit to at most 4 to 5 standard genres (e.g. 'Pop & Dance', 'Melodic & Romance', 'Acoustic & Chill', 'Classics & Heritage', 'Energetic & Beats').

        List of tracks:
        \(jsonStr)

        Return ONLY a JSON object strictly matching this schema:
        {
          "categories": [
            {
              "id": "lang_id",
              "language": "Hindi",
              "icon": "music.mic",
              "genres": [
                {
                  "id": "genre_id",
                  "name": "Melodic & Romance",
                  "icon": "heart.fill",
                  "description": "Soulful melodies and romantic ballads",
                  "trackIds": ["id1", "id2"]
                }
              ]
            }
          ]
        }
        """

        let rawResponse = try await executeLLMRequest(prompt: prompt)
        
        struct AIResponseWrapper: Codable {
            let categories: [AILanguageCategory]
        }

        let wrapper = try parseJSON(AIResponseWrapper.self, from: rawResponse)
        return AICuratedLibrary(lastUpdated: Date(), categories: wrapper.categories)
    }

    private func executeLLMRequest(prompt: String, retryCount: Int = 0) async throws -> String {
        let provider = config.selectedProvider
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var request: URLRequest
        let currentModel = (provider == .gemini) ? config.activeGeminiModel : provider.defaultModel

        switch provider {
        case .gemini:
            guard let url = URL(string: "\(provider.defaultEndpoint)/\(currentModel):generateContent?key=\(apiKey)") else {
                throw URLError(.badURL)
            }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "contents": [
                    ["parts": [["text": prompt]]]
                ],
                "generationConfig": [
                    "responseMimeType": "application/json",
                    "thinkingConfig": [
                        "thinkingBudget": 0
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .groq, .openai, .ollama:
            let endpointStr = provider == .ollama && !config.customEndpoint.isEmpty ? config.customEndpoint : provider.defaultEndpoint
            guard let url = URL(string: endpointStr) else {
                throw URLError(.badURL)
            }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if provider != .ollama {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let body: [String: Any] = [
                "model": provider.defaultModel,
                "messages": [
                    ["role": "system", "content": "You are a music categorizer that outputs strictly valid JSON."],
                    ["role": "user", "content": prompt]
                ],
                "response_format": ["type": "json_object"]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        request.timeoutInterval = 60.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            var errDetail = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 500)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                errDetail = message
            } else if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                errDetail = str
            }

            // Auto-fallback and retry for Gemini if model not found or deprecated
            if provider == .gemini && retryCount < 3 && (errDetail.contains("no longer available") || errDetail.contains("not found") || errDetail.contains("not supported") || (response as? HTTPURLResponse)?.statusCode == 404) {
                // If Google explicitly suggests a model (e.g. "use models/gemini-3.8-flash")
                if let regex = try? NSRegularExpression(pattern: "models/([a-zA-Z0-9.-]+)"),
                   let match = regex.matches(in: errDetail, range: NSRange(errDetail.startIndex..., in: errDetail)).last,
                   let range = Range(match.range(at: 1), in: errDetail) {
                    let recommended = String(errDetail[range])
                    if recommended != currentModel {
                        config.activeGeminiModel = recommended
                        return try await executeLLMRequest(prompt: prompt, retryCount: retryCount + 1)
                    }
                }

                if currentModel != "gemini-3.8-flash" {
                    config.activeGeminiModel = "gemini-3.8-flash"
                    return try await executeLLMRequest(prompt: prompt, retryCount: retryCount + 1)
                }

                if let discovered = await discoverGeminiModel(apiKey: apiKey), discovered != currentModel {
                    config.activeGeminiModel = discovered
                    return try await executeLLMRequest(prompt: prompt, retryCount: retryCount + 1)
                }
            }

            throw NSError(domain: "AIPlaylistEngine", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errDetail])
        }

        // Parse LLM provider response structure
        if provider == .gemini {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
        } else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let text = message["content"] as? String {
                return text
            }
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseJSON<T: Decodable>(_ type: T.Type, from rawString: String) throws -> T {
        var clean = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean = clean.replacingOccurrences(of: "```json", with: "")
        }
        if clean.hasPrefix("```") {
            clean = clean.replacingOccurrences(of: "```", with: "")
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8) else {
            throw NSError(domain: "AIPlaylistEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed text response"])
        }
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Native Offline Heuristic Fallback

    private func performHeuristicClustering(for tracks: [Track]) -> AICuratedLibrary {
        var library = AICuratedLibrary()
        for track in tracks {
            let c = classifyTrackHeuristically(track)
            library.insert(
                trackId: track.id,
                language: c.language,
                genreName: c.genre,
                genreIcon: c.icon,
                genreDescription: c.description
            )
        }
        return library
    }

    public func classifyTrackHeuristically(_ track: Track) -> AISongClassification {
        let combined = "\(track.title) \(track.artist)".lowercased()

        // 1. Language determination
        var language = "English"
        var langIcon = "globe"

        let hindiKeywords = [
            "arijit", "shreya", "atif", "sonu nigam", "sunidhi", "kumar sanu", "udit narayan", "lata", "asha", 
            "kishore", "rafi", "mukesh", "jagjit", "pritam", "badshah", "neha kakkar", "jubin", "armaan malik",
            "darshan raval", "vishal", "shekhar", "sachin-jigar", "shankar mahadevan", "amit trivedi", "anuv jain",
            "prateek kuhad", "b praak", "t-series", "t series", "bollywood", "filmi", "dil", "pyar", "ishq", "mohabbat",
            "meri", "tera", "tum", "hum", "suno", "jaan", "sanam", "zindagi", "raat", "aankhen", "saath", "channa",
            "chaleya", "kesariya", "apna bana le", "deva deva", "kabira", "kalank", "shayad", "raataan lambiyan",
            "tujhe", "humsafar", "phir", "kabhi", "jeena", "dua karo", "khairiyat"
        ]

        let englishArtists = [
            "dua lipa", "taylor swift", "ed sheeran", "the weeknd", "weeknd", "drake", "eminem", 
            "billie eilish", "ariana grande", "justin bieber", "post malone", "bruno mars", 
            "coldplay", "imagine dragons", "queen", "beatles", "michael jackson", "rihanna",
            "shakira", "adele", "maroon 5", "charlie puth", "shawn mendes", "olivia rodrigo",
            "kendrick lamar", "travis scott", "kanye", "beyonce", "lady gaga", "katy perry"
        ]

        let punjabiKeywords = [
            "diljit", "sidhu", "karan aujla", "ap dhillon", "shubh", "guru randhawa", "amrinder", "gurdas", 
            "babbu maan", "jassi gill", "harrdy sandhu", "parmish", "ammy virk", "honey singh", "bohemia",
            "imran khan", "mickey singh", "prophec", "bhangra", "jatt", "gabru", "punjabi", "pind", "gaddi",
            "patola", "high rated", "prada", "goat", "chorni", "same beef", "elevated", "no love", "drip too hard",
            "softly", "brown munde", "insane", "cheques", "one love", "tauba tauba"
        ]

        let southIndianKeywords = [
            "anirudh", "sid sriram", "ilaiyaraaja", "devi sri prasad", "dsp", "gv prakash", "spb", "balasubrahmanyam",
            "chithra", "thaman", "harris jayaraj", "yuvan", "santhosh narayanan", "tamil", "telugu", "malayalam", "kannada",
            "arabic kuthu", "naatu naatu", "butta bomma", "samajavaragamana", "rowdy baby", "kaavaalaa", "hukum"
        ]

        let instrumentalKeywords = [
            "lo-fi", "lofi", "instrumental", "piano", "acoustic guitar", "orchestral", "ost", "theme", 
            "ambient", "synthwave", "sleep", "meditation", "relaxing", "interstellar", "hans zimmer"
        ]

        if englishArtists.contains(where: { combined.contains($0) }) {
            language = "English"
            langIcon = "globe"
        } else if instrumentalKeywords.contains(where: { combined.contains($0) }) {
            language = "Instrumental"
            langIcon = "guitars"
        } else if punjabiKeywords.contains(where: { combined.contains($0) }) {
            language = "Punjabi"
            langIcon = "music.mic"
        } else if southIndianKeywords.contains(where: { combined.contains($0) }) {
            language = "South Indian"
            langIcon = "music.mic"
        } else if hindiKeywords.contains(where: { combined.contains($0) }) || containsDevanagari(combined) {
            language = "Hindi"
            langIcon = "music.mic"
        }

        // 2. Standard 5 Genres determination
        var genre = "Melodic & Romance"
        var genreIcon = "heart.fill"
        var genreDesc = "Soulful melodies and romantic tracks"

        let danceKeywords = ["dance", "remix", "party", "club", "pop", "disco", "beat", "upbeat", "levitating", "badshah", "honey singh", "edm", "house", "dj"]
        let acousticKeywords = ["acoustic", "unplugged", "chill", "night", "slow", "soft", "lofi", "lo-fi", "coffee", "sleep", "rain", "anuv jain", "prateek kuhad"]
        let classicKeywords = ["199", "198", "197", "196", "classic", "old", "retro", "vintage", "kishore", "lata", "rafi", "mukesh", "asha", "jagjit", "ghazal", "heritage", "golden era"]
        let energeticKeywords = ["rap", "hip hop", "drill", "trap", "hype", "bass", "gym", "workout", "phonk", "diss", "sidhu", "karan aujla", "emiway", "raftaar", "divine", "stan", "eminem", "drake"]

        if danceKeywords.contains(where: { combined.contains($0) }) {
            genre = "Pop & Dance"
            genreIcon = "flame.fill"
            genreDesc = "High-energy chart-toppers and dance beats"
        } else if acousticKeywords.contains(where: { combined.contains($0) }) {
            genre = "Acoustic & Chill"
            genreIcon = "moon.stars.fill"
            genreDesc = "Gentle acoustic, lo-fi, and midnight vibes"
        } else if classicKeywords.contains(where: { combined.contains($0) }) {
            genre = "Classics & Heritage"
            genreIcon = "sparkles"
            genreDesc = "Timeless classics and golden era favorites"
        } else if energeticKeywords.contains(where: { combined.contains($0) }) {
            genre = "Energetic & Beats"
            genreIcon = "bolt.fill"
            genreDesc = "Bass-heavy rap, beats, and motivational energy"
        }

        return AISongClassification(language: language, genre: genre, icon: genreIcon, description: genreDesc)
    }

    private func containsDevanagari(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x0900...0x097F).contains(scalar.value) { return true }
        }
        return false
    }
}
