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

    // MARK: - OpenRouter Live Free Model Discovery & API Key Verification

    /// Fetches all active 100% free models directly from OpenRouter API and updates availableFreeModels
    @MainActor
    public func fetchAvailableFreeModels(apiKey: String) async -> [OpenRouterModel] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            return config.availableFreeModels
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("https://sonorist.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Sonorist Music Player", forHTTPHeaderField: "X-Title")

        struct ModelItem: Codable {
            let id: String
            let name: String
            let description: String?
            let contextLength: Int?
            let pricing: PricingItem?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case description
                case contextLength = "context_length"
                case pricing
            }

            struct PricingItem: Codable {
                let prompt: String?
                let completion: String?
            }
        }

        struct ResponseData: Codable {
            let data: [ModelItem]
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return config.availableFreeModels
            }

            let decoded = try JSONDecoder().decode(ResponseData.self, from: data)
            let freeItems = decoded.data.filter { item in
                if item.id.hasSuffix(":free") || item.id == "openrouter/free" {
                    return true
                }
                if let p = item.pricing {
                    let promptCost = Double(p.prompt ?? "1") ?? 1.0
                    let compCost = Double(p.completion ?? "1") ?? 1.0
                    return promptCost == 0.0 && compCost == 0.0
                }
                return false
            }

            if !freeItems.isEmpty {
                let mapped = freeItems.map {
                    OpenRouterModel(id: $0.id, name: $0.name, description: $0.description, contextLength: $0.contextLength)
                }.sorted { $0.name < $1.name }

                self.config.availableFreeModels = mapped
                if !mapped.contains(where: { $0.id == self.config.selectedModelId }) {
                    if let firstChoice = mapped.first(where: { $0.id.contains("llama-3.3-70b") }) ?? mapped.first {
                        self.config.selectedModelId = firstChoice.id
                    }
                }
                return mapped
            }
        } catch {
            #if DEBUG
            print("[AIPlaylistEngine] Failed to fetch live OpenRouter models: \(error)")
            #endif
        }

        return config.availableFreeModels
    }

    /// Tests the connection to OpenRouter API and discovers live free models.
    /// Returns a user-friendly status message and sets connectionMessage.
    @MainActor
    public func testAPIConnection() async -> (success: Bool, message: String) {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            let msg = "Please enter your OpenRouter API key first."
            self.connectionMessage = msg
            return (false, msg)
        }

        self.testingConnection = true
        self.connectionMessage = nil
        defer { self.testingConnection = false }

        // 1. Fetch live free models from OpenRouter to populate the dropdown!
        let discovered = await fetchAvailableFreeModels(apiKey: apiKey)

        // 2. Perform a test ping with the currently selected free model
        do {
            let testPrompt = "Respond strictly with valid JSON: {\"status\": \"ok\"}"
            _ = try await executeLLMRequest(prompt: testPrompt, isTestPing: true)
            
            let modelName = config.availableFreeModels.first(where: { $0.id == config.selectedModelId })?.name ?? config.selectedModelId
            let successMsg = "✓ Connected! Using \(modelName) (\(discovered.count) free models ready)."
            self.connectionMessage = successMsg
            self.lastSyncError = nil

            // 3. Immediately re-curate the library so songs sort into their proper languages
            Task {
                await self.curateEntireLibrary(force: true)
            }
            return (true, successMsg)
        } catch {
            let nsErr = error as NSError
            let detail = nsErr.localizedDescription
            let errMsg: String
            if nsErr.code == 400 || nsErr.code == 401 || nsErr.code == 403 {
                errMsg = "✗ Authentication Failed (\(nsErr.code)): \(detail)"
            } else if (error as? URLError)?.code == .timedOut {
                errMsg = "✗ Connection Timed Out: OpenRouter took too long to respond. Choose another free model from the dropdown."
            } else if (error as? URLError)?.code == .notConnectedToInternet {
                errMsg = "✗ Network Offline: Could not reach OpenRouter. Check your internet connection."
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
        public let whatIsThisSong: String?
        public let language: String
        public let genre: String
        public let icon: String
        public let description: String

        public init(language: String, genre: String, icon: String, description: String, whatIsThisSong: String? = nil) {
            self.language = language
            self.genre = genre
            self.icon = icon
            self.description = description
            self.whatIsThisSong = whatIsThisSong
        }
    }

    private func querySingleTrackClassification(track: Track) async throws -> AISongClassification {
        let prompt = """
        You are an expert musicologist and multilingual music cataloger.
        Song Title: "\(track.title)"
        Artist: "\(track.artist)"

        Analyze this song by carefully answering these three specific questions:
        1. What exactly is this song by this artist? Describe its musical context, cultural origin, album, or soundtrack.
        2. In which language is this song sung? (e.g. Bengali, Hindi, English, Punjabi, Tamil, Telugu, Malayalam, Kannada, Urdu, Spanish, Korean, or Instrumental).
        3. Which musical genre does it belong to, chosen strictly from these 5 standard genres:
           - Pop & Dance
           - Melodic & Romance
           - Acoustic & Chill
           - Classics & Heritage
           - Energetic & Beats

        CRITICAL LINGUISTIC RULES:
        - Check the artist and song title carefully.
        - Many Indian songs have their titles and artist names transliterated into English/Latin letters.
        - NEVER classify an Indian song as "English" simply because its title or artist is written in the Roman alphabet!
        - Examples:
          * "Majhe Majhe Tobo" by Arindom: Exactly Rabindra Sangeet -> Language MUST be "Bengali", Genre: "Melodic & Romance".
          * "Destiny - Mann Atkeya" by Shashwat Sachdev: Hindi romantic ballad -> Language MUST be "Hindi", Genre: "Melodic & Romance".
          * "Shape of You" by Ed Sheeran: British pop hit -> Language MUST be "English", Genre: "Pop & Dance".
          * "Lead Me" by Sanctus Real: Christian rock / acoustic ballad -> Language MUST be "English", Genre: "Acoustic & Chill".

        Respond strictly in valid JSON matching this schema:
        {
          "whatIsThisSong": "State what exactly this song is by this artist",
          "language": "LanguageName",
          "genre": "GenreName",
          "icon": "music.mic",
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
        You are an expert musicologist and multilingual music cataloger.
        Examine this list of songs by checking each song's name and artist carefully.
        For each song, answer:
        1. What exactly is this song by this artist? (Origin, film/album, background).
        2. In which language is this song sung? (e.g. Bengali, Hindi, English, Punjabi, Tamil, Telugu, Malayalam, Kannada, Urdu, Spanish, Korean, or Instrumental).
        3. Which musical genre does it belong to, chosen strictly from these 5 standard genres:
           - Pop & Dance
           - Melodic & Romance
           - Acoustic & Chill
           - Classics & Heritage
           - Energetic & Beats

        CRITICAL LINGUISTIC RULES:
        - Check the artist and song title carefully.
        - Many Indian and international tracks have their titles and artist names transliterated into the Latin/English alphabet.
        - DO NOT classify a track as "English" merely because its title or artist name is written using English letters!
        - Key examples:
          * "Majhe Majhe Tobo" by Arindom -> Exactly Rabindra Sangeet. Language MUST be "Bengali".
          * "Shraboner Dharar Moto" by Mekhla Dasgupta -> Exactly Rabindra Sangeet. Language MUST be "Bengali".
          * "Hey Shokha" by Somlata Acharyya Chowdhury -> Exactly Rabindra Sangeet. Language MUST be "Bengali".
          * "Destiny - Mann Atkeya" by Shashwat Sachdev -> Bollywood Hindi romantic ballad. Language MUST be "Hindi" ("Mann Atkeya" is Hindi; do not let "Destiny" fool you into English).
          * "Shape of You" by Ed Sheeran -> English pop song. Language MUST be "English".
          * "Lead Me" by Sanctus Real -> English acoustic rock. Language MUST be "English".

        List of tracks to analyze:
        \(jsonStr)

        Return strictly a valid JSON object matching this schema:
        {
          "songs": [
            {
              "id": "track_id_from_input",
              "whatIsThisSong": "State what exactly this song is by this artist",
              "language": "Bengali",
              "genre": "Melodic & Romance"
            }
          ]
        }
        """

        let rawResponse = try await executeLLMRequest(prompt: prompt)

        struct AnalyzedTrack: Codable {
            let id: String
            let whatIsThisSong: String?
            let language: String
            let genre: String
        }

        struct SongsWrapper: Codable {
            let songs: [AnalyzedTrack]
        }

        struct CategoriesWrapper: Codable {
            let categories: [AILanguageCategory]
        }

        // 1. Preferred song-by-song analysis (most accurate, factual, and deterministic)
        if let songsResult = try? parseJSON(SongsWrapper.self, from: rawResponse), !songsResult.songs.isEmpty {
            var newLibrary = AICuratedLibrary()
            for analyzed in songsResult.songs {
                let meta = self.genreMetadata(for: analyzed.genre)
                let cleanLang = analyzed.language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                newLibrary.insert(
                    trackId: analyzed.id,
                    language: cleanLang.isEmpty ? "Other" : cleanLang,
                    genreName: meta.name,
                    genreIcon: meta.icon,
                    genreDescription: meta.description
                )
            }
            return newLibrary
        }

        // 2. Compatibility fallback: older categories wrapper schema
        if let catResult = try? parseJSON(CategoriesWrapper.self, from: rawResponse), !catResult.categories.isEmpty {
            return AICuratedLibrary(lastUpdated: Date(), categories: catResult.categories)
        }

        throw NSError(domain: "AIPlaylistEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse music catalog analysis from AI"])
    }

    private func genreMetadata(for rawGenre: String) -> (name: String, icon: String, description: String) {
        let g = rawGenre.lowercased()
        if g.contains("dance") || g.contains("pop") {
            return ("Pop & Dance", "flame.fill", "High-energy chart-toppers and dance beats")
        } else if g.contains("acoustic") || g.contains("chill") {
            return ("Acoustic & Chill", "moon.stars.fill", "Gentle acoustic, lo-fi, and midnight vibes")
        } else if g.contains("classic") || g.contains("heritage") || g.contains("old") {
            return ("Classics & Heritage", "sparkles", "Timeless classics and golden era favorites")
        } else if g.contains("energetic") || g.contains("rap") || g.contains("beat") {
            return ("Energetic & Beats", "bolt.fill", "Bass-heavy rap, beats, and motivational energy")
        } else {
            return ("Melodic & Romance", "heart.fill", "Soulful melodies and romantic tracks")
        }
    }

    private func executeLLMRequest(prompt: String, isTestPing: Bool = false, retryCount: Int = 0) async throws -> String {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: config.selectedProvider.defaultEndpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://sonorist.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Sonorist Music Player", forHTTPHeaderField: "X-Title")

        let modelToUse = config.selectedModelId

        var body: [String: Any] = [
            "model": modelToUse,
            "messages": [
                ["role": "system", "content": "You are an expert musicologist and multilingual music cataloger that outputs strictly valid JSON."],
                ["role": "user", "content": prompt]
            ]
        ]
        if retryCount == 0 {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = isTestPing ? 15.0 : 45.0

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

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            // If selected model is down or rate-limited, fallback to Llama 3.3 70B
            if retryCount == 0 && (statusCode == 429 || statusCode == 404 || statusCode == 400 || errDetail.contains("no provider serves this model")) {
                if modelToUse != "meta-llama/llama-3.3-70b-instruct:free" {
                    config.selectedModelId = "meta-llama/llama-3.3-70b-instruct:free"
                    return try await executeLLMRequest(prompt: prompt, isTestPing: isTestPing, retryCount: retryCount + 1)
                }
            }

            throw NSError(domain: "AIPlaylistEngine", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errDetail])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
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

        // Resiliently isolate JSON substring if wrapped in conversational text
        if let startIndex = clean.firstIndex(of: "{"),
           let endIndex = clean.lastIndex(of: "}") {
            clean = String(clean[startIndex...endIndex])
        }

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

        let bengaliKeywords = [
            "arindom", "somlata", "mekhla dasgupta", "mekhla", "anupam roy", "rabindranath", "tagore", 
            "rupam islam", "fossils", "nachiketa", "hemanta mukherjee", "babul supriyo", "monali thakur", 
            "jeeth ganguly", "indraadip", "lopamudra", "cactus", "bhoomi", "anindya", "chandrabindoo", 
            "subhamita", "srikanto", "raghab", "iman chakraborty", "shovan", "lagnajita", "debayan", 
            "svf music", "svf", "tobo", "majhe majhe", "shraboner", "dharar moto", "hey shokha", "shokha", 
            "bhalobashi", "amar mon", "ektara", "kolkata", "bristi", "nodir", "dujon", "mayabono", "bodhu", 
            "alor gaan", "bengali", "bangla", "rabindra sangeet", "rabindra"
        ]

        let hindiKeywords = [
            "shashwat sachdev", "mann atkeya", "atkeya", "sachdev", "arijit", "shreya", "atif", "sonu nigam", 
            "sunidhi", "kumar sanu", "udit narayan", "lata", "asha", "kishore", "rafi", "mukesh", "jagjit", 
            "pritam", "badshah", "neha kakkar", "jubin", "armaan malik", "darshan raval", "vishal", "shekhar", 
            "sachin-jigar", "shankar mahadevan", "amit trivedi", "anuv jain", "prateek kuhad", "b praak", 
            "t-series", "t series", "bollywood", "filmi", "dil ", "mera dil", "pyar", "ishq", "mohabbat", "meri", "tera", 
            "tum", "hum", "suno", "jaan", "sanam", "zindagi", "raat", "aankhen", "saath", "channa", "chaleya", 
            "kesariya", "apna bana le", "deva deva", "kabira", "kalank", "shayad", "raataan lambiyan", "tujhe", 
            "humsafar", "phir", "kabhi", "jeena", "dua karo", "khairiyat", "deewani", "sufi", "qawwali"
        ]

        let englishArtists = [
            "dua lipa", "taylor swift", "ed sheeran", "the weeknd", "weeknd", "drake", "eminem", 
            "billie eilish", "ariana grande", "justin bieber", "post malone", "bruno mars", 
            "coldplay", "imagine dragons", "queen", "beatles", "michael jackson", "rihanna",
            "shakira", "adele", "maroon 5", "charlie puth", "shawn mendes", "olivia rodrigo",
            "kendrick lamar", "travis scott", "kanye", "beyonce", "lady gaga", "katy perry",
            "sanctus real", "linkin park", "marshmello", "chainsmokers", "alan walker", "avicii",
            "sia", "halsey", "camila cabello", "selena gomez", "sam smith", "calvin harris"
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

        if containsBengaliScript(combined) || bengaliKeywords.contains(where: { combined.contains($0) }) {
            language = "Bengali"
            langIcon = "music.mic"
        } else if punjabiKeywords.contains(where: { combined.contains($0) }) {
            language = "Punjabi"
            langIcon = "music.mic"
        } else if southIndianKeywords.contains(where: { combined.contains($0) }) {
            language = "South Indian"
            langIcon = "music.mic"
        } else if containsDevanagari(combined) || hindiKeywords.contains(where: { combined.contains($0) }) {
            language = "Hindi"
            langIcon = "music.mic"
        } else if instrumentalKeywords.contains(where: { combined.contains($0) }) {
            language = "Instrumental"
            langIcon = "guitars"
        } else if englishArtists.contains(where: { combined.contains($0) }) {
            language = "English"
            langIcon = "globe"
        } else {
            language = "English"
            langIcon = "globe"
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

    private func containsBengaliScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x0980...0x09FF).contains(scalar.value) { return true }
        }
        return false
    }
}
