import Foundation
import Combine

public final class AIPlaylistEngine: ObservableObject, @unchecked Sendable {
    public static let shared = AIPlaylistEngine()

    private let config = AIProviderConfig.shared
    private let cacheManager = MediaCacheManager.shared
    private let queue = DispatchQueue(label: "com.sonorist.ai.playlist.queue", qos: .userInitiated)

    @Published public var curatedLibrary: AICuratedLibrary = AICuratedLibrary()
    @Published public var isCurating: Bool = false
    @Published public var lastSyncError: String?
    @Published public var showingSettingsSheet: Bool = false
    @Published public var spinRefresh: Bool = false
    @Published public var testingConnection: Bool = false
    @Published public var connectionMessage: String?

    private var storageURL: URL {
        cacheManager.parentDirectory.appendingPathComponent("AICuratedPlaylists.json")
    }

    private init() {
        loadCachedLibrary()
    }

    // MARK: - Persistence

    public func loadCachedLibrary() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: storageURL.path),
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder().decode(AICuratedLibrary.self, from: data) else {
                return
            }
            Task { @MainActor in
                self.curatedLibrary = decoded
            }
        }
    }

    public func saveLibrary() {
        queue.async {
            do {
                let data = try JSONEncoder().encode(self.curatedLibrary)
                try data.write(to: self.storageURL, options: .atomic)
            } catch {
                #if DEBUG
                print("[AIPlaylistEngine] Failed to save curated library: \(error)")
                #endif
            }
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

    // MARK: - Instant Download Hook

    /// Called silently immediately upon track download completion.
    public func categorizeNewTrack(_ track: Track) async {
        guard config.isAutoCurateOnDownloadEnabled else { return }

        // If API configured, attempt fast single-track classification
        if config.isConfigured {
            if let classification = try? await querySingleTrackClassification(track: track) {
                Task { @MainActor in
                    self.curatedLibrary.insert(
                        trackId: track.id,
                        language: classification.language,
                        genreName: classification.genre,
                        genreIcon: classification.icon,
                        genreDescription: classification.description
                    )
                    self.saveLibrary()
                }
                return
            }
        }

        // Offline / heuristic fallback
        let fallback = classifyTrackHeuristically(track)
        Task { @MainActor in
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

    /// Removes track when un-downloaded from library
    public func handleTrackRemoved(videoId: String) {
        Task { @MainActor in
            self.curatedLibrary.remove(trackId: videoId)
            self.saveLibrary()
        }
    }

    // MARK: - Daily Background Sync

    public func performDailySyncIfNeeded() async {
        guard config.isDailyRefreshEnabled else { return }
        if let lastSync = config.lastSyncDate, Date().timeIntervalSince(lastSync) < 86400 {
            return // Less than 24 hours
        }
        await curateEntireLibrary(force: false)
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

    private func executeLLMRequest(prompt: String) async throws -> String {
        let provider = config.selectedProvider
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var request: URLRequest

        switch provider {
        case .gemini:
            guard let url = URL(string: "\(provider.defaultEndpoint)/\(provider.defaultModel):generateContent?key=\(apiKey)") else {
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
                    "responseMimeType": "application/json"
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

        request.timeoutInterval = 25.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw NSError(domain: "AIPlaylistEngine", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errStr])
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

        let hindiKeywords = ["kumar sanu", "udit narayan", "lata", "asha", "arijit", "shreya", "sonu nigam", "rahat", "kishore", "rafi", "atif", "t series", "bollywood", "dil", "pyar", "tera", "meri", "hum", "tum", "ishq"]
        let punjabiKeywords = ["diljit", "sidhu", "ap dhillon", "karan aujla", "shubh", "amrinder", "gurdas", "bhangra", "jatt", "punjabi"]
        let instrumentalKeywords = ["lo-fi", "lofi", "instrumental", "piano", "acoustic", "orchestral", "ost", "theme", "ambient"]

        if instrumentalKeywords.contains(where: { combined.contains($0) }) {
            language = "Instrumental"
            langIcon = "guitars"
        } else if punjabiKeywords.contains(where: { combined.contains($0) }) {
            language = "Punjabi"
            langIcon = "music.mic"
        } else if hindiKeywords.contains(where: { combined.contains($0) }) || containsDevanagari(combined) {
            language = "Hindi"
            langIcon = "music.mic"
        }

        // 2. Standard 5 Genres determination
        var genre = "Melodic & Romance"
        var genreIcon = "heart.fill"
        var genreDesc = "Soulful melodies and romantic tracks"

        if combined.contains("dance") || combined.contains("remix") || combined.contains("party") || combined.contains("club") || combined.contains("pop") || combined.contains("levitating") {
            genre = "Pop & Dance"
            genreIcon = "flame.fill"
            genreDesc = "High-energy chart-toppers and dance beats"
        } else if combined.contains("acoustic") || combined.contains("unplugged") || combined.contains("chill") || combined.contains("night") || combined.contains("slow") {
            genre = "Acoustic & Chill"
            genreIcon = "moon.stars.fill"
            genreDesc = "Gentle acoustic, lo-fi, and midnight vibes"
        } else if combined.contains("199") || combined.contains("classic") || combined.contains("old") || combined.contains("retro") || combined.contains("kishore") || combined.contains("lata") || combined.contains("sanu") {
            genre = "Classics & Heritage"
            genreIcon = "sparkles"
            genreDesc = "Timeless classics and golden era favorites"
        } else if combined.contains("rap") || combined.contains("hip hop") || combined.contains("drill") || combined.contains("trap") || combined.contains("hype") {
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
