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
            // Reconcile direct tracks laying in folder
            let prevDirect = curatedLibrary.categories[lIdx].directTrackIds.count
            curatedLibrary.categories[lIdx].directTrackIds.removeAll(where: { !cachedIds.contains($0) })
            if curatedLibrary.categories[lIdx].directTrackIds.count != prevDirect {
                libraryChanged = true
            }

            // Reconcile subfolders
            for gIdx in (0..<curatedLibrary.categories[lIdx].genres.count).reversed() {
                let prev = curatedLibrary.categories[lIdx].genres[gIdx].trackIds.count
                curatedLibrary.categories[lIdx].genres[gIdx].trackIds.removeAll(where: { !cachedIds.contains($0) })
                if curatedLibrary.categories[lIdx].genres[gIdx].trackIds.count != prev {
                    libraryChanged = true
                }
            }
            // Retain custom subfolders even if they have 0 tracks
            let prevCount = curatedLibrary.categories[lIdx].genres.count
            curatedLibrary.categories[lIdx].genres.removeAll(where: { !$0.isCustom && $0.trackIds.isEmpty })
            if curatedLibrary.categories[lIdx].genres.count != prevCount {
                libraryChanged = true
            }
        }
        // Retain category if it contains direct tracks or custom subfolders
        let prevCatCount = curatedLibrary.categories.count
        curatedLibrary.categories.removeAll(where: { cat in
            cat.directTrackIds.isEmpty && (
                cat.genres.isEmpty || cat.genres.allSatisfy { $0.trackIds.isEmpty && !$0.isCustom }
            )
        })
        if curatedLibrary.categories.count != prevCatCount {
            libraryChanged = true
        }
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
                    var merged = result
                    // Preserve existing custom genre folders (e.g. "Spiritual") that might currently have 0 tracks
                    for cat in self.curatedLibrary.categories {
                        for customGenre in cat.genres where customGenre.isCustom {
                            if let lIdx = merged.categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cat.language) == .orderedSame }) {
                                if !merged.categories[lIdx].genres.contains(where: { $0.name.caseInsensitiveCompare(customGenre.name) == .orderedSame }) {
                                    var emptyCopy = customGenre
                                    emptyCopy.trackIds = []
                                    merged.categories[lIdx].genres.append(emptyCopy)
                                } else if let gIdx = merged.categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(customGenre.name) == .orderedSame }) {
                                    merged.categories[lIdx].genres[gIdx].isCustom = true
                                    merged.categories[lIdx].genres[gIdx].icon = customGenre.icon
                                    merged.categories[lIdx].genres[gIdx].description = customGenre.description
                                    merged.categories[lIdx].genres[gIdx].aliases = customGenre.aliases
                                }
                            } else {
                                var emptyCat = cat
                                emptyCat.genres = [customGenre]
                                emptyCat.genres[0].trackIds = []
                                merged.categories.append(emptyCat)
                            }
                        }
                    }
                    self.curatedLibrary = merged
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

    // MARK: - User Playlist Folder Customization Controls

    @MainActor
    public func renameGenre(
        in language: String,
        oldName: String,
        newName: String,
        newIcon: String? = nil,
        newDescription: String? = nil
    ) {
        curatedLibrary.renameGenre(
            in: language,
            oldName: oldName,
            newName: newName,
            newIcon: newIcon,
            newDescription: newDescription
        )
        saveLibrary()
    }

    @MainActor
    public func addCustomGenre(
        in language: String,
        name: String,
        icon: String = "music.note",
        description: String = ""
    ) {
        curatedLibrary.addCustomGenre(
            in: language,
            name: name,
            icon: icon,
            description: description
        )
        saveLibrary()
    }

    @MainActor
    public func deleteGenre(
        in language: String,
        name: String,
        migrateToGenre: String? = nil
    ) {
        curatedLibrary.deleteGenre(
            in: language,
            name: name,
            migrateToGenre: migrateToGenre
        )
        saveLibrary()
    }

    @MainActor
    public func moveTrack(
        trackId: String,
        in language: String,
        fromGenre: String,
        toGenre: String
    ) {
        curatedLibrary.moveTrack(
            trackId: trackId,
            in: language,
            fromGenre: fromGenre,
            toGenre: toGenre
        )
        saveLibrary()
    }

    @MainActor
    public func applyGlobalClassicsPreference(useSpiritual: Bool) {
        let targetName = useSpiritual ? "Spiritual" : "Classics & Heritage"
        let oldName = useSpiritual ? "Classics & Heritage" : "Spiritual"
        let icon = useSpiritual ? "sun.max.fill" : "sparkles"
        let desc = useSpiritual ? "Devotional, spiritual, hymns, prayers, and Rabindra Sangeet" : "Timeless classics and golden era favorites"

        for cat in curatedLibrary.categories {
            if cat.genres.contains(where: { $0.name.caseInsensitiveCompare(oldName) == .orderedSame }) {
                curatedLibrary.renameGenre(
                    in: cat.language,
                    oldName: oldName,
                    newName: targetName,
                    newIcon: icon,
                    newDescription: desc
                )
            } else if !cat.genres.contains(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) {
                curatedLibrary.addCustomGenre(
                    in: cat.language,
                    name: targetName,
                    icon: icon,
                    description: desc
                )
            }
        }
        saveLibrary()
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
        public let genre: String // Represents user subfolder (empty if laying directly in folder)
        public let icon: String
        public let description: String

        public init(language: String, genre: String = "", icon: String = "folder.fill", description: String = "", whatIsThisSong: String? = nil) {
            self.language = language
            self.genre = genre
            self.icon = icon
            self.description = description
            self.whatIsThisSong = whatIsThisSong
        }

        enum CodingKeys: String, CodingKey {
            case whatIsThisSong, language, genre, subfolder, icon, description
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            whatIsThisSong = try container.decodeIfPresent(String.self, forKey: .whatIsThisSong)
            language = try container.decodeIfPresent(String.self, forKey: .language) ?? "English"
            let rawSubfolder = try container.decodeIfPresent(String.self, forKey: .subfolder)
            let rawGenre = try container.decodeIfPresent(String.self, forKey: .genre)
            let chosen = rawSubfolder ?? rawGenre ?? ""
            genre = (chosen.caseInsensitiveCompare("null") == .orderedSame || chosen.caseInsensitiveCompare("none") == .orderedSame) ? "" : chosen
            icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
            description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(whatIsThisSong, forKey: .whatIsThisSong)
            try container.encode(language, forKey: .language)
            try container.encode(genre, forKey: .genre)
            try container.encode(icon, forKey: .icon)
            try container.encode(description, forKey: .description)
        }
    }

    // MARK: - Active User Subfolders Catalog & Resolution

    /// Returns the user-created subfolders for a specific language (or all across the library if language is nil).
    public func activeSubfolders(for language: String? = nil) -> [AIGenreGroup] {
        if let lang = language,
           let cat = curatedLibrary.categories.first(where: { $0.language.caseInsensitiveCompare(lang) == .orderedSame }) {
            return cat.genres.filter { $0.isCustom }
        }
        var custom: [AIGenreGroup] = []
        for cat in curatedLibrary.categories {
            for g in cat.genres where g.isCustom {
                if !custom.contains(where: { $0.name.caseInsensitiveCompare(g.name) == .orderedSame }) {
                    custom.append(g)
                }
            }
        }
        return custom
    }

    public func activeSubfoldersDescription(for language: String? = nil) -> String {
        let list = activeSubfolders(for: language)
        if list.isEmpty {
            return "None created yet. Subfolder should be null."
        }
        return list.map { "- \($0.name): \($0.description.isEmpty ? "User subfolder" : $0.description)" }.joined(separator: "\n")
    }

    public func activeGenres(for language: String? = nil) -> [(name: String, icon: String, description: String)] {
        return activeSubfolders(for: language).map { ($0.name, $0.icon, $0.description) }
    }

    public func activeGenresDescription(for language: String? = nil) -> String {
        return activeSubfoldersDescription(for: language)
    }

    private func querySingleTrackClassification(track: Track) async throws -> AISongClassification {
        let subfoldersDesc = activeSubfoldersDescription()
        let prompt = """
        You are an expert musicologist and multilingual music cataloger.
        Song Title: "\(track.title)"
        Artist: "\(track.artist)"

        Analyze this song by answering:
        1. What exactly is this song by this artist? Describe its musical context, cultural origin, album, or soundtrack.
        2. In which language is this song sung? (e.g. Bengali, Hindi, English, Punjabi, Tamil, Telugu, Malayalam, Kannada, Urdu, Spanish, Korean, or Instrumental).
        3. Available user-created subfolders:
        \(subfoldersDesc)

        CRITICAL LINGUISTIC & SUBFOLDER RULES:
        - Accurately determine the true sung Language of the track.
        - NEVER classify an Indian song as "English" simply because its title or artist is written in the Roman alphabet!
          * "Majhe Majhe Tobo" by Arindom: Rabindra Sangeet -> Language MUST be "Bengali".
          * "Hey Shokha" by Somlata Acharyya Chowdhury: Rabindra Sangeet -> Language MUST be "Bengali".
          * "Destiny - Mann Atkeya" by Shashwat Sachdev: Hindi ballad -> Language MUST be "Hindi".
          * "Shape of You" by Ed Sheeran: British pop hit -> Language MUST be "English".
          * "Lead Me" by Sanctus Real: Christian rock -> Language MUST be "English".
        - SUBFOLDER ROUTING:
          * If this song fits into any of the available user-created subfolders listed above (e.g., if "Spiritual" is listed and the song is devotional, Christian rock, or Rabindra Sangeet), set "subfolder" to that exact name.
          * If no matching subfolder is listed, or if the song does not match, set "subfolder" to null.

        Respond strictly in valid JSON matching this schema:
        {
          "whatIsThisSong": "State what exactly this song is by this artist",
          "language": "LanguageName",
          "subfolder": null
        }
        """

        let rawResponse = try await executeLLMRequest(prompt: prompt)
        return try parseJSON(AISongClassification.self, from: rawResponse)
    }

    private func queryAICuration(for tracks: [Track]) async throws -> AICuratedLibrary {
        let trackPayload = tracks.map { ["id": $0.id, "title": $0.title, "artist": $0.artist] }
        let payloadData = try JSONSerialization.data(withJSONObject: trackPayload)
        let jsonStr = String(data: payloadData, encoding: .utf8) ?? "[]"
        let subfoldersDesc = activeSubfoldersDescription()

        let prompt = """
        You are an expert musicologist and multilingual music cataloger.
        Examine this list of songs by checking each song's name and artist carefully.
        For each song, answer:
        1. What exactly is this song by this artist? (Origin, film/album, background).
        2. In which language is this song sung? (e.g. Bengali, Hindi, English, Punjabi, Tamil, Telugu, Malayalam, Kannada, Urdu, Spanish, Korean, or Instrumental).
        3. Available user-created subfolders:
        \(subfoldersDesc)

        CRITICAL LINGUISTIC & SUBFOLDER RULES:
        - Accurately determine the true sung Language of the track.
        - DO NOT classify an Indian track as "English" merely because its title or artist name is written using English letters!
          * "Majhe Majhe Tobo" by Arindom -> Rabindra Sangeet sung in Bengali. Language MUST be "Bengali".
          * "Hey Shokha" by Somlata Acharyya Chowdhury -> Rabindra Sangeet sung in Bengali. Language MUST be "Bengali".
          * "Shraboner Dharar Moto" by Mekhla Dasgupta -> Rabindra Sangeet sung in Bengali. Language MUST be "Bengali".
          * "Destiny - Mann Atkeya" by Shashwat Sachdev -> Bollywood Hindi romantic ballad. Language MUST be "Hindi".
          * "Shape of You" by Ed Sheeran -> English pop song. Language MUST be "English".
          * "Lead Me" by Sanctus Real -> English Christian acoustic rock. Language MUST be "English".
        - SUBFOLDER ROUTING:
          * If a song fits one of the user-created subfolders listed above (e.g. "Spiritual" for devotional songs or Rabindra Sangeet), set "subfolder" to that name.
          * If no subfolder matches or none are listed, set "subfolder" to null. Songs with null subfolders will cleanly lay directly in their language folder!

        List of tracks to analyze:
        \(jsonStr)

        Return strictly a valid JSON object matching this schema:
        {
          "songs": [
            {
              "id": "track_id_from_input",
              "whatIsThisSong": "State what exactly this song is by this artist",
              "language": "Bengali",
              "subfolder": null
            }
          ]
        }
        """

        let rawResponse = try await executeLLMRequest(prompt: prompt)

        struct AnalyzedTrack: Codable {
            let id: String
            let whatIsThisSong: String?
            let language: String
            let subfolder: String?
            let genre: String?
        }

        struct SongsWrapper: Codable {
            let songs: [AnalyzedTrack]
        }

        struct CategoriesWrapper: Codable {
            let categories: [AILanguageCategory]
        }

        // 1. Preferred song-by-song analysis
        if let songsResult = try? parseJSON(SongsWrapper.self, from: rawResponse), !songsResult.songs.isEmpty {
            var newLibrary = AICuratedLibrary()
            for analyzed in songsResult.songs {
                let cleanLang = analyzed.language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                let rawFolder = (analyzed.subfolder ?? analyzed.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let meta = self.genreMetadata(for: rawFolder, language: cleanLang)
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

    private func genreMetadata(for rawGenre: String, language: String? = nil) -> (name: String, icon: String, description: String) {
        let g = rawGenre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !g.isEmpty, g != "null", g != "none", g != "other" else {
            return ("", "folder.fill", "")
        }
        let active = activeSubfolders(for: language)

        // 1. Exact match with active user subfolders
        if let direct = active.first(where: { $0.name.caseInsensitiveCompare(rawGenre) == .orderedSame }) {
            return (direct.name, direct.icon, direct.description)
        }

        // 2. Spiritual / Devotional / Sacred matching if user has a spiritual subfolder
        if g.contains("spirit") || g.contains("devot") || g.contains("bhajan") || g.contains("kirtan") || g.contains("rabindra") || g.contains("prayer") || g.contains("gospel") || g.contains("hymn") || g.contains("sacred") {
            if let spiritualGenre = active.first(where: { $0.name.localizedCaseInsensitiveContains("spirit") || $0.name.localizedCaseInsensitiveContains("devot") || $0.name.localizedCaseInsensitiveContains("rabindra") }) {
                return (spiritualGenre.name, spiritualGenre.icon, spiritualGenre.description)
            }
        }

        // 3. Check aliases
        if let aliasMatch = active.first(where: { group in
            group.aliases.contains(where: { $0.caseInsensitiveCompare(rawGenre) == .orderedSame })
        }) {
            return (aliasMatch.name, aliasMatch.icon, aliasMatch.description)
        }

        // 4. If no user subfolder matches, do NOT invent artificial folders! Return empty so it lays in the main language folder!
        return ("", "folder.fill", "")
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

        // Preserve user custom genre folders across all languages even if currently empty
        for cat in self.curatedLibrary.categories {
            for customGenre in cat.genres where customGenre.isCustom {
                if let lIdx = library.categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cat.language) == .orderedSame }) {
                    var emptyCopy = customGenre
                    emptyCopy.trackIds = []
                    library.categories[lIdx].genres.append(emptyCopy)
                } else {
                    var emptyCat = cat
                    emptyCat.genres = [customGenre]
                    emptyCat.genres[0].trackIds = []
                    library.categories.append(emptyCat)
                }
            }
        }

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

        // 2. Subfolder determination (only if a matching user-created subfolder exists)
        let userSubfolders = activeSubfolders(for: language)
        var genre = ""
        var genreIcon = "folder.fill"
        var genreDesc = ""

        let spiritualKeywords = [
            "spiritual", "devotional", "bhajan", "kirtan", "aarti", "mantra", "chalisa", 
            "prayer", "prarthana", "gospel", "worship", "hymn", "meditation", "sacred",
            "rabindra sangeet", "rabindra", "rabindranath", "tagore", "majhe majhe tobo", 
            "hey shokha", "shraboner dharar moto", "lead me", "sanctus real", "om namah",
            "krishna", "shiva", "ganesh", "hanuman", "ram", "waheguru", "allah", "khwaja"
        ]

        let danceKeywords = ["dance", "remix", "party", "club", "pop", "disco", "beat", "upbeat", "levitating", "badshah", "honey singh", "edm", "house", "dj"]
        let acousticKeywords = ["acoustic", "unplugged", "chill", "night", "slow", "soft", "lofi", "lo-fi", "coffee", "sleep", "rain", "anuv jain", "prateek kuhad"]
        let energeticKeywords = ["rap", "hip hop", "drill", "trap", "hype", "bass", "gym", "workout", "phonk", "diss", "sidhu", "karan aujla", "emiway", "raftaar", "divine", "stan", "eminem", "drake"]

        for sf in userSubfolders {
            let sfLower = sf.name.lowercased()
            if sfLower.contains("spirit") || sfLower.contains("devot") {
                if spiritualKeywords.contains(where: { combined.contains($0) }) {
                    genre = sf.name
                    genreIcon = sf.icon
                    genreDesc = sf.description
                    break
                }
            } else if sfLower.contains("rabindra") {
                if bengaliKeywords.contains(where: { combined.contains($0) }) && (combined.contains("rabindra") || combined.contains("tobo") || combined.contains("shokha") || combined.contains("arindom")) {
                    genre = sf.name
                    genreIcon = sf.icon
                    genreDesc = sf.description
                    break
                }
            } else if sfLower.contains("dance") || sfLower.contains("pop") || sfLower.contains("party") {
                if danceKeywords.contains(where: { combined.contains($0) }) {
                    genre = sf.name
                    genreIcon = sf.icon
                    genreDesc = sf.description
                    break
                }
            } else if sfLower.contains("acoustic") || sfLower.contains("chill") {
                if acousticKeywords.contains(where: { combined.contains($0) }) {
                    genre = sf.name
                    genreIcon = sf.icon
                    genreDesc = sf.description
                    break
                }
            } else if sfLower.contains("rap") || sfLower.contains("beat") || sfLower.contains("energetic") {
                if energeticKeywords.contains(where: { combined.contains($0) }) {
                    genre = sf.name
                    genreIcon = sf.icon
                    genreDesc = sf.description
                    break
                }
            } else if combined.contains(sfLower) {
                genre = sf.name
                genreIcon = sf.icon
                genreDesc = sf.description
                break
            }
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
