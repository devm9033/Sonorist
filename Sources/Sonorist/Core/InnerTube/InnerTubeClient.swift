import Foundation

/// YouTube Music InnerTube API Client for macOS
/// Handles search, metadata retrieval, and direct stream extraction.
public actor InnerTubeClient {
    public static let shared = InnerTubeClient()
    
    private let session: URLSession
    private let cipherEngine: YouTubeCipherEngine
    
    // In-memory query cache for instant responses and zero duplicate network requests (TTL: 5 mins)
    private var searchCache: [String: (timestamp: Date, tracks: [Track])] = [:]
    
    public init(session: URLSession = .shared, cipherEngine: YouTubeCipherEngine = .shared) {
        self.session = session
        self.cipherEngine = cipherEngine
    }
    
    // MARK: - High-Res Artwork Helper
    
    public nonisolated static func highResArtworkURL(from original: String?) -> URL? {
        guard let raw = original, !raw.isEmpty else { return nil }
        var enhanced = raw
        
        // Enhance googleusercontent & ggpht thumbnails from 60/120px to 800px retina HD
        if enhanced.contains("googleusercontent.com") || enhanced.contains("ggpht.com") {
            let pattern = #"=w\d+-h\d+[^?]*"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: enhanced.utf16.count)
                enhanced = regex.stringByReplacingMatches(in: enhanced, options: [], range: range, withTemplate: "=w800-h800-l90-rj")
            } else if enhanced.contains("=s") {
                let sPattern = #"=s\d+[^?]*"#
                if let sRegex = try? NSRegularExpression(pattern: sPattern) {
                    let range = NSRange(location: 0, length: enhanced.utf16.count)
                    enhanced = sRegex.stringByReplacingMatches(in: enhanced, options: [], range: range, withTemplate: "=s800")
                }
            }
        } else if enhanced.contains("i.ytimg.com") {
            enhanced = enhanced
                .replacingOccurrences(of: "/hqdefault.jpg", with: "/maxresdefault.jpg")
                .replacingOccurrences(of: "/sddefault.jpg", with: "/maxresdefault.jpg")
                .replacingOccurrences(of: "/default.jpg", with: "/hqdefault.jpg")
        }
        
        return SecurityAudit.validateURL(enhanced) ?? SecurityAudit.validateURL(raw)
    }
    
    // MARK: - Search
    
    /// Searches YouTube Music for songs and artists
    public func search(query: String) async throws -> [Track] {
        let sanitized = SecurityAudit.sanitizeSearchQuery(query)
        guard !sanitized.isEmpty else { return [] }
        
        // Return instantly from in-memory cache if queried within 5 minutes
        if let cached = searchCache[sanitized], Date().timeIntervalSince(cached.timestamp) < 300 {
            return cached.tracks
        }
        
        let url = URL(string: "https://music.youtube.com/youtubei/v1/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20240901.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240901.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": sanitized,
            "params": "Eg-KAQwIABAAGAEgASgB" // Strictly filter for Songs (excludes podcasts and long talk videos)
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let parsed = parseSearchResults(from: data)
                if !parsed.isEmpty {
                    searchCache[sanitized] = (Date(), parsed)
                    if searchCache.count > 60 {
                        let now = Date()
                        searchCache = searchCache.filter { now.timeIntervalSince($0.value.timestamp) < 300 }
                    }
                    return parsed
                }
            }
        } catch {
            #if DEBUG
            print("[InnerTubeClient Search Error]: \(error)")
            #endif
        }
        
        // Defensive fallback for offline preview
        return fallbackTracks(for: sanitized)
    }
    
    // MARK: - Search Suggestions (Autocomplete)
    
    /// Fetches live search suggestions from YouTube Music as the user types
    public func fetchSearchSuggestions(query: String) async -> [String] {
        let sanitized = SecurityAudit.sanitizeSearchQuery(query)
        guard !sanitized.isEmpty else { return [] }
        
        let url = URL(string: "https://music.youtube.com/youtubei/v1/music/get_search_suggestions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20240901.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240901.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "input": sanitized
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            return parseSearchSuggestions(from: data)
        } catch {
            return []
        }
    }
    
    private func parseSearchSuggestions(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        var suggestions: [String] = []
        
        func extract(from obj: Any) {
            if let dict = obj as? [String: Any] {
                if let searchEndpoint = dict["searchEndpoint"] as? [String: Any],
                   let query = searchEndpoint["query"] as? String {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !suggestions.contains(trimmed) {
                        suggestions.append(trimmed)
                    }
                }
                for value in dict.values {
                    extract(from: value)
                }
            } else if let arr = obj as? [Any] {
                for item in arr {
                    extract(from: item)
                }
            }
        }
        
        extract(from: json)
        return Array(suggestions.prefix(8))
    }
    
    // MARK: - Smart Radio & Autoplay Recommendations
    
    /// Fetches algorithmic radio recommendations / up-next tracks for a given video
    public func fetchRadioTracks(for videoId: String) async throws -> [Track] {
        guard SecurityAudit.validateVideoID(videoId) else {
            return fallbackTracks(for: videoId)
        }
        
        let url = URL(string: "https://music.youtube.com/youtubei/v1/next")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20240901.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240901.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId,
            "playlistId": "RDAMVM" + videoId, // YouTube Music Seeded Radio Playlist
            "isAudioOnly": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let parsed = parseSearchResults(from: data)
                let filtered = parsed.filter { $0.id != videoId }
                if !filtered.isEmpty {
                    return filtered
                }
            }
        } catch {
            #if DEBUG
            print("[InnerTubeClient Radio Error]: \(error)")
            #endif
        }
        
        return fallbackTracks(for: videoId)
    }
    
    // MARK: - Track Credits & Description
    
    /// Fetches the official track description containing composer, lyricist, and label credits
    public func fetchTrackDescription(videoId: String) async -> String? {
        guard SecurityAudit.validateVideoID(videoId) else { return nil }
        
        let androidEndpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        var request = URLRequest(url: androidEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
        request.setValue("3", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("21.26.364", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.timeoutInterval = 6.0
        
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "21.26.364",
                    "androidSdkVersion": 30,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return nil }
            let playerResponse = try JSONDecoder().decode(InnerTubePlayerResponse.self, from: data)
            return playerResponse.videoDetails?.shortDescription
        } catch {
            return nil
        }
    }
    
    // MARK: - Stream Extraction
    
    /// Resolves the playable direct audio URL and all available quality streams for a given YouTube video ID
    public func resolveStreamURL(for videoId: String, preferredQuality: AudioQuality = .standard) async throws -> (URL, String, [AudioStreamOption]) {
        guard SecurityAudit.validateVideoID(videoId) else {
            throw NSError(domain: "InnerTubeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid video ID format."])
        }
        
        let androidEndpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        var request = URLRequest(url: androidEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
        request.setValue("3", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("21.26.364", forHTTPHeaderField: "X-YouTube-Client-Version")
        
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "21.26.364",
                    "androidSdkVersion": 30,
                    "userAgent": "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
                    "osName": "Android",
                    "osVersion": "11",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        
        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
            throw NSError(domain: "InnerTubeClient", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpRes.statusCode) from player endpoint."])
        }
        
        let decoder = JSONDecoder()
        let playerResponse = try decoder.decode(InnerTubePlayerResponse.self, from: data)
        
        if let status = playerResponse.playabilityStatus?.status, status != "OK" {
            let reason = playerResponse.playabilityStatus?.reason ?? status
            throw NSError(domain: "InnerTubeClient", code: 403, userInfo: [NSLocalizedDescriptionKey: "Playback unavailable: \(reason)"])
        }
        
        guard let streamingData = playerResponse.streamingData else {
            throw NSError(domain: "InnerTubeClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "No streaming data returned."])
        }
        
        var availableOptions: [AudioStreamOption] = []
        var resolvedCandidates: [(quality: AudioQuality, url: URL, label: String, itag: Int, bitrate: Int)] = []
        
        // 1. Process adaptiveFormats (audio-only streams - preferred for quality & bandwidth)
        if let adaptiveFormats = streamingData.adaptiveFormats {
            for format in adaptiveFormats where format.mimeType?.contains("audio") == true {
                let quality: AudioQuality
                let label: String
                let bitrate = format.bitrate ?? (format.averageBitrate ?? 128000)
                
                if format.itag == 251 {
                    quality = .high
                    label = "Opus 160kbps (High-Res)"
                } else if format.itag == 140 {
                    quality = .standard
                    label = "AAC 128kbps (Standard)"
                } else if format.itag == 139 || format.itag == 249 {
                    quality = .dataSaver
                    label = "AAC 48kbps (Data Saver)"
                } else {
                    quality = .auto
                    label = "Audio (\(bitrate / 1000)kbps)"
                }
                
                availableOptions.append(AudioStreamOption(quality: quality, itag: format.itag, mimeType: format.mimeType ?? "audio", bitrate: bitrate, label: label))
                
                if let directUrl = format.url, let streamURL = SecurityAudit.validateURL(directUrl) {
                    let unthrottled = cipherEngine.descrambleNParam(in: streamURL.absoluteString)
                    if let finalURL = URL(string: unthrottled) {
                        resolvedCandidates.append((quality, finalURL, label, format.itag, bitrate))
                    }
                } else if let rawCipher = format.signatureCipher ?? format.cipher,
                          let deciphered = cipherEngine.decipher(rawCipher: rawCipher) {
                    resolvedCandidates.append((quality, deciphered, label, format.itag, bitrate))
                }
            }
        }
        
        // 2. Process multiplexed formats (itag 18 - Direct MP4 with AAC 128k audio as internal fallback)
        if let formats = streamingData.formats {
            for format in formats where format.itag == 18 {
                if let directUrl = format.url, let streamURL = SecurityAudit.validateURL(directUrl) {
                    let unthrottled = cipherEngine.descrambleNParam(in: streamURL.absoluteString)
                    if let finalURL = URL(string: unthrottled) {
                        resolvedCandidates.append((.standard, finalURL, "AAC 128k", 18, format.bitrate ?? 128000))
                    }
                } else if let rawCipher = format.signatureCipher ?? format.cipher,
                          let deciphered = cipherEngine.decipher(rawCipher: rawCipher) {
                    resolvedCandidates.append((.standard, deciphered, "AAC 128k", 18, format.bitrate ?? 128000))
                }
            }
        }
        
        // Match user's preferred quality
        if preferredQuality != .auto {
            if let matched = resolvedCandidates.first(where: { $0.quality == preferredQuality }) {
                return (matched.url, matched.label, availableOptions)
            }
        }
        
        // Fallback hierarchy: Standard (itag 140 / 18) -> High (itag 251) -> Any candidate
        if let standard = resolvedCandidates.first(where: { $0.quality == .standard }) {
            return (standard.url, standard.label, availableOptions)
        }
        if let high = resolvedCandidates.first(where: { $0.quality == .high }) {
            return (high.url, high.label, availableOptions)
        }
        if let first = resolvedCandidates.first {
            return (first.url, first.label, availableOptions)
        }
        
        throw NSError(domain: "InnerTubeClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "No playable stream URL available."])
    }
    
    /// Backward compatible overload
    public func resolveStreamURL(for videoId: String) async throws -> (URL, String) {
        let (url, badge, _) = try await resolveStreamURL(for: videoId, preferredQuality: .standard)
        return (url, badge)
    }
    
    // MARK: - Parsing Logic
    
    private func parseSearchResults(from data: Data) -> [Track] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        var tracks: [Track] = []
        var seenIds = Set<String>()
        
        func extractTracks(from obj: Any) {
            if let dict = obj as? [String: Any] {
                if let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let track = makeTrack(from: renderer), !seenIds.contains(track.id) {
                        seenIds.insert(track.id)
                        tracks.append(track)
                    }
                }
                if let panelRenderer = dict["playlistPanelVideoRenderer"] as? [String: Any] {
                    if let track = makeTrack(fromPlaylistPanel: panelRenderer), !seenIds.contains(track.id) {
                        seenIds.insert(track.id)
                        tracks.append(track)
                    }
                }
                for value in dict.values {
                    extractTracks(from: value)
                }
            } else if let array = obj as? [Any] {
                for element in array {
                    extractTracks(from: element)
                }
            }
        }
        
        extractTracks(from: json)
        return tracks
    }
    
    private func makeTrack(from renderer: [String: Any]) -> Track? {
        guard let flexColumns = renderer["flexColumns"] as? [[String: Any]], !flexColumns.isEmpty else {
            return nil
        }
        
        // 1. Title Extraction
        var title = "Unknown Title"
        if let firstCol = flexColumns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let textObj = firstCol["text"] as? [String: Any],
           let runs = textObj["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Intelligent Artist, Album & Duration Extraction
        var artist = "YouTube Music"
        var album: String? = nil
        var durationSeconds: Double = 210
        
        if flexColumns.count >= 2,
           let secondCol = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let textObj = secondCol["text"] as? [String: Any],
           let runs = textObj["runs"] as? [[String: Any]] {
            
            var candidates: [String] = []
            for run in runs {
                guard let text = run["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == "•" || trimmed == "&" || trimmed.hasPrefix("•") { continue }
                
                // Timestamp detection (e.g. "3:45" or "1:12:30")
                if trimmed.contains(":") && trimmed.count <= 8 {
                    let parts = trimmed.split(separator: ":").compactMap { Double($0) }
                    if parts.count == 2 {
                        durationSeconds = (parts[0] * 60) + parts[1]
                    } else if parts.count == 3 {
                        durationSeconds = (parts[0] * 3600) + (parts[1] * 60) + parts[2]
                    }
                    continue
                }
                
                // Exclude metadata noise
                let lower = trimmed.lowercased()
                if lower == "song" || lower == "video" || lower == "single" || lower == "album" ||
                   lower.contains("views") || lower.contains("plays") || lower.contains("audience") || lower.contains("subscribers") {
                    continue
                }
                
                candidates.append(trimmed)
            }
            
            if let firstValid = candidates.first {
                artist = firstValid
            }
            if candidates.count > 1 {
                album = candidates[1]
            }
        }
        
        // Handle "Artist - Title" patterns if artist is generic or video format
        if title.contains(" - ") {
            let components = title.components(separatedBy: " - ")
            if components.count == 2 {
                let candidateArtist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateTitle = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if artist == "YouTube Music" || artist.lowercased() == "song" || artist.lowercased() == "video" || artist.isEmpty {
                    artist = candidateArtist
                    title = candidateTitle
                }
            }
        }
        
        // 3. Video ID extraction from multiple potential paths
        var videoId: String?
        if let playlistItemData = renderer["playlistItemData"] as? [String: Any],
           let id = playlistItemData["videoId"] as? String {
            videoId = id
        } else if let navigationEndpoint = renderer["navigationEndpoint"] as? [String: Any],
                  let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
                  let id = watchEndpoint["videoId"] as? String {
            videoId = id
        } else if let firstCol = flexColumns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                  let textObj = firstCol["text"] as? [String: Any],
                  let runs = textObj["runs"] as? [[String: Any]],
                  let firstRun = runs.first,
                  let nav = firstRun["navigationEndpoint"] as? [String: Any],
                  let watch = nav["watchEndpoint"] as? [String: Any],
                  let id = watch["videoId"] as? String {
            videoId = id
        } else if let overlay = renderer["overlay"] as? [String: Any],
                  let thumbOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                  let content = thumbOverlay["content"] as? [String: Any],
                  let playBtn = content["musicPlayButtonRenderer"] as? [String: Any],
                  let playNav = playBtn["playNavigationEndpoint"] as? [String: Any],
                  let watch = playNav["watchEndpoint"] as? [String: Any],
                  let id = watch["videoId"] as? String {
            videoId = id
        }
        
        guard let validId = videoId, SecurityAudit.validateVideoID(validId) else {
            return nil
        }
        
        // 4. High-Res Artwork extraction
        var artworkURL: URL?
        if let thumbnailContainer = renderer["thumbnail"] as? [String: Any],
           let musicThumbnail = thumbnailContainer["musicThumbnailRenderer"] as? [String: Any],
           let thumbnail = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let bestThumb = thumbnails.last,
           let urlString = bestThumb["url"] as? String {
            artworkURL = Self.highResArtworkURL(from: urlString)
        }
        
        // Exclude talk shows, debates, and podcasts (> 20 mins or metadata flags)
        if durationSeconds > 1200 { return nil }
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("podcast") || lowerTitle.contains("episode") || lowerTitle.contains("debate") || lowerTitle.contains("interview") {
            return nil
        }
        
        return Track(
            id: validId,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds,
            artworkURL: artworkURL,
            streamURL: nil,
            audioFormat: "AAC 128kbps"
        )
    }
    
    /// Parses YouTube Music's algorithmic radio and Up-Next items (`playlistPanelVideoRenderer`)
    private func makeTrack(fromPlaylistPanel renderer: [String: Any]) -> Track? {
        guard let videoId = renderer["videoId"] as? String, SecurityAudit.validateVideoID(videoId) else {
            return nil
        }
        
        // Title
        var title = "Unknown Title"
        if let titleObj = renderer["title"] as? [String: Any] {
            if let runs = titleObj["runs"] as? [[String: Any]], let first = runs.first?["text"] as? String {
                title = first.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let simple = titleObj["simpleText"] as? String {
                title = simple.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Artist
        var artist = "YouTube Music"
        if let shortByline = renderer["shortBylineText"] as? [String: Any],
           let runs = shortByline["runs"] as? [[String: Any]],
           let first = runs.first?["text"] as? String {
            artist = first.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let longByline = renderer["longBylineText"] as? [String: Any],
                  let runs = longByline["runs"] as? [[String: Any]],
                  let first = runs.first?["text"] as? String {
            artist = first.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Duration
        var durationSeconds: Double = 210
        if let lengthObj = renderer["lengthText"] as? [String: Any] {
            var lenStr: String?
            if let runs = lengthObj["runs"] as? [[String: Any]], let first = runs.first?["text"] as? String {
                lenStr = first
            } else if let simple = lengthObj["simpleText"] as? String {
                lenStr = simple
            }
            if let s = lenStr {
                let parts = s.split(separator: ":").compactMap { Double($0) }
                if parts.count == 2 {
                    durationSeconds = (parts[0] * 60) + parts[1]
                } else if parts.count == 3 {
                    durationSeconds = (parts[0] * 3600) + (parts[1] * 60) + parts[2]
                }
            }
        }
        
        // Artwork
        var artworkURL: URL?
        if let thumbContainer = renderer["thumbnail"] as? [String: Any],
           let thumbnails = thumbContainer["thumbnails"] as? [[String: Any]],
           let best = thumbnails.last,
           let urlString = best["url"] as? String {
            artworkURL = Self.highResArtworkURL(from: urlString)
        }
        
        // Exclude talk shows, debates, and podcasts (> 20 mins or metadata flags)
        if durationSeconds > 1200 { return nil }
        let lower = title.lowercased()
        if lower.contains("podcast") || lower.contains("episode") || lower.contains("debate") || lower.contains("interview") {
            return nil
        }
        
        return Track(
            id: videoId,
            title: title,
            artist: artist,
            album: nil,
            durationSeconds: durationSeconds,
            artworkURL: artworkURL,
            streamURL: nil,
            audioFormat: "AAC 128kbps"
        )
    }
    
    // MARK: - Initial Discover / Fallback Mock Data
    
    nonisolated public func fetchFeaturedTracks() -> [Track] {
        return [
            Track(
                id: "fJ9rUzIMcZQ",
                title: "Bohemian Rhapsody",
                artist: "Queen",
                album: "A Night at the Opera",
                durationSeconds: 355,
                artworkURL: URL(string: "https://i.ytimg.com/vi/fJ9rUzIMcZQ/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            ),
            Track(
                id: "kXYiU_JCYtU",
                title: "Numb",
                artist: "Linkin Park",
                album: "Meteora",
                durationSeconds: 187,
                artworkURL: URL(string: "https://i.ytimg.com/vi/kXYiU_JCYtU/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            ),
            Track(
                id: "kJQP7kiw5Fk",
                title: "Despacito",
                artist: "Luis Fonsi ft. Daddy Yankee",
                album: "VIDA",
                durationSeconds: 228,
                artworkURL: URL(string: "https://i.ytimg.com/vi/kJQP7kiw5Fk/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            ),
            Track(
                id: "JGwWNGJdvx8",
                title: "Shape of You",
                artist: "Ed Sheeran",
                album: "÷ (Divide)",
                durationSeconds: 233,
                artworkURL: URL(string: "https://i.ytimg.com/vi/JGwWNGJdvx8/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            ),
            Track(
                id: "09R8_2nJtjg",
                title: "Sugar",
                artist: "Maroon 5",
                album: "V",
                durationSeconds: 235,
                artworkURL: URL(string: "https://i.ytimg.com/vi/09R8_2nJtjg/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            ),
            Track(
                id: "CevxZvSJLk8",
                title: "Roar",
                artist: "Katy Perry",
                album: "Prism",
                durationSeconds: 223,
                artworkURL: URL(string: "https://i.ytimg.com/vi/CevxZvSJLk8/maxresdefault.jpg"),
                audioFormat: "AAC 128kbps"
            )
        ]
    }
    
    nonisolated private func fallbackTracks(for query: String) -> [Track] {
        let all = fetchFeaturedTracks()
        let filtered = all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
        return filtered.isEmpty ? all : filtered
    }
}
