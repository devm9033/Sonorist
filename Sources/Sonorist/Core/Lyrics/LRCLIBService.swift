import Foundation

/// Word-by-word syllable karaoke token with start time and duration
public struct LyricWord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let word: String
    public let time: Double      // start time in seconds
    public let duration: Double  // duration in seconds
    
    public init(id: String = UUID().uuidString, word: String, time: Double, duration: Double) {
        self.id = id
        self.word = word
        self.time = time
        self.duration = duration
    }
}

/// Track story, trivia, and meaning (Music DNA)
public struct TrackStory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let summary: String
    public let source: String
    public let releaseYear: String?
    public let genre: String?
    public let extract: String
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        summary: String,
        source: String = "Wikipedia / Genius",
        releaseYear: String? = nil,
        genre: String? = nil,
        extract: String
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.summary = summary
        self.source = source
        self.releaseYear = releaseYear
        self.genre = genre
        self.extract = extract
    }
}

/// Model representing a single synchronized lyric line with translations, romanization, and word tokens
public struct LyricLine: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let time: Double
    public let text: String
    public var translation: String?       // Real-time AI translated line
    public var romanization: String?      // Romaji / Pinyin / Phonetic transliteration
    public var words: [LyricWord]         // Word-by-word / syllable karaoke tokens
    public var isSynced: Bool             // True if timestamps are synchronized; false if plain text
    
    public init(
        id: String = UUID().uuidString,
        time: Double,
        text: String,
        translation: String? = nil,
        romanization: String? = nil,
        words: [LyricWord] = [],
        isSynced: Bool = true
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.translation = translation
        self.romanization = romanization
        self.words = words
        self.isSynced = isSynced
    }
    
    enum CodingKeys: String, CodingKey {
        case id, time, text, translation, romanization, words, isSynced
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.time = try container.decode(Double.self, forKey: .time)
        self.text = try container.decode(String.self, forKey: .text)
        self.translation = try container.decodeIfPresent(String.self, forKey: .translation)
        self.romanization = try container.decodeIfPresent(String.self, forKey: .romanization)
        self.words = try container.decodeIfPresent([LyricWord].self, forKey: .words) ?? []
        self.isSynced = try container.decodeIfPresent(Bool.self, forKey: .isSynced) ?? (self.time > 0 || !self.words.isEmpty)
    }
}

/// Multi-provider lyrics engine inspired by Echo-Music and Apple Music
/// Cascades through LRCLIB, NetEase Cloud Music, and YouTube Music InnerTube lyrics.
/// Features word-by-word karaoke cadence, native Romanization (Romaji/Pinyin), AI translation, and Music DNA.
public actor LRCLIBService {
    public static let shared = LRCLIBService()
    
    private let session: URLSession
    private let fileManager = FileManager.default
    private let lyricsCacheDir: URL
    
    public init(session: URLSession = .shared) {
        self.session = session
        
        let fm = FileManager.default
        let defaultAppSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appFolder = defaultAppSupport?.appendingPathComponent("Sonorist", isDirectory: true)
        if let folder = appFolder,
           (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil &&
           fm.isWritableFile(atPath: folder.path) {
            self.lyricsCacheDir = folder.appendingPathComponent("LyricsCache", isDirectory: true)
        } else {
            let fallbackDir = URL(fileURLWithPath: "/tmp/Sonorist", isDirectory: true)
            self.lyricsCacheDir = fallbackDir.appendingPathComponent("LyricsCache", isDirectory: true)
        }
        try? fm.createDirectory(at: self.lyricsCacheDir, withIntermediateDirectories: true)
    }
    
    /// Fetches synchronized lyrics for a track across multi-source providers, checking offline cache first
    public func fetchLyrics(for track: Track) async -> [LyricLine] {
        // 1. Check local cache
        if let cached = loadCachedLyrics(for: track.id) {
            return cached
        }
        
        var title = cleanSongTitle(track.title)
        var artist = cleanArtistName(track.artist)
        
        // Handle "Artist - Title" in track.title if artist is generic
        if (artist.lowercased() == "youtube music" || artist.lowercased() == "song" || artist.isEmpty) && title.contains(" - ") {
            let parts = title.components(separatedBy: " - ")
            if parts.count == 2 {
                artist = cleanArtistName(parts[0])
                title = cleanSongTitle(parts[1])
            }
        }
        
        let isValidArtist = !artist.isEmpty && artist.lowercased() != "youtube music" && artist.lowercased() != "song" && artist.lowercased() != "video"
        let dur = track.durationSeconds > 0 ? track.durationSeconds : nil
        let searchQuery = isValidArtist ? "\(title) \(artist)" : title
        
        // MARK: - PASS 1: Search for TRUE SYNCED lyrics across providers
        // 1. LRCLIB GET endpoint with duration first for exact release timing (syncedOnly: true)
        if isValidArtist {
            if let lines = await queryGetEndpoint(title: title, artist: artist, duration: dur, syncedOnly: true) {
                let enriched = enrichLines(lines)
                saveCachedLyrics(enriched, for: track.id)
                return enriched
            }
            if dur != nil, let lines = await queryGetEndpoint(title: title, artist: artist, duration: nil, syncedOnly: true) {
                let enriched = enrichLines(lines)
                saveCachedLyrics(enriched, for: track.id)
                return enriched
            }
        }
        
        // 2. LRCLIB Fallback search endpoint with duration proximity (syncedOnly: true)
        if let lines = await querySearchEndpoint(query: searchQuery, preferredTitle: title, preferredArtist: isValidArtist ? artist : nil, preferredDuration: dur, syncedOnly: true) {
            let enriched = enrichLines(lines)
            saveCachedLyrics(enriched, for: track.id)
            return enriched
        }
        
        // 2b. If artist was generic but album exists, search title + album
        if !isValidArtist, let album = track.album, !album.isEmpty {
            if let lines = await querySearchEndpoint(query: "\(title) \(album)", preferredTitle: title, preferredArtist: nil, preferredDuration: dur, syncedOnly: true) {
                let enriched = enrichLines(lines)
                saveCachedLyrics(enriched, for: track.id)
                return enriched
            }
        }
        
        if isValidArtist, let lines = await querySearchEndpoint(query: title, preferredTitle: title, preferredArtist: artist, preferredDuration: dur, syncedOnly: true) {
            let enriched = enrichLines(lines)
            saveCachedLyrics(enriched, for: track.id)
            return enriched
        }
        
        // 3. NetEase Cloud Music: Massive database of synced lyrics & official translations
        if let netEaseLines = await queryNetEaseLyrics(title: title, artist: artist) {
            let enriched = enrichLines(netEaseLines)
            saveCachedLyrics(enriched, for: track.id)
            return enriched
        }
        
        // MARK: - PASS 2: If NO synced lyrics exist anywhere, accept plain/unsynced lyrics
        // Never assign fake 3.5s timers; mark them honestly as isSynced: false
        if isValidArtist {
            if let lines = await queryGetEndpoint(title: title, artist: artist, duration: nil, syncedOnly: false) {
                let enriched = enrichLines(lines)
                saveCachedLyrics(enriched, for: track.id)
                return enriched
            }
        }
        
        if let lines = await querySearchEndpoint(query: searchQuery, preferredTitle: title, preferredArtist: isValidArtist ? artist : nil, preferredDuration: dur, syncedOnly: false) {
            let enriched = enrichLines(lines)
            saveCachedLyrics(enriched, for: track.id)
            return enriched
        }
        
        if let ytLines = await queryYouTubeMusicLyrics(videoId: track.id) {
            let enriched = enrichLines(ytLines)
            saveCachedLyrics(enriched, for: track.id)
            return enriched
        }
        
        // 4. Return graceful empty list (UI handles this as "No lyrics available")
        return []
    }
    
    // MARK: - LRCLIB API Calls
    
    private func queryGetEndpoint(title: String, artist: String, duration: Double? = nil, syncedOnly: Bool = false) async -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let duration = duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(round(duration)))))
        }
        components?.queryItems = items
        
        guard let url = components?.url, SecurityAudit.validateURL(url.absoluteString) != nil else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Sonorist/2.0 (macOS; Native Player)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 7.0
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return parseLRCLIBResponse(data: data, syncedOnly: syncedOnly)
        } catch {
            return nil
        }
    }
    
    private func querySearchEndpoint(query: String, preferredTitle: String, preferredArtist: String? = nil, preferredDuration: Double? = nil, syncedOnly: Bool = false) async -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        
        guard let url = components?.url, SecurityAudit.validateURL(url.absoluteString) != nil else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Sonorist/2.0 (macOS; Native Player)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 7.0
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            
            // Search returns an array of records
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                // Relevance filter: Reject records that don't match title or artist to prevent showing random songs
                let relevantItems = array.filter { item in
                    self.isCandidateRelevant(item: item, preferredTitle: preferredTitle, preferredArtist: preferredArtist)
                }
                
                let syncedItems = relevantItems.filter { item in
                    if let synced = item["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return true
                    }
                    return false
                }
                
                let sortedSynced: [[String: Any]]
                if let prefDur = preferredDuration, prefDur > 0 {
                    sortedSynced = syncedItems.sorted { a, b in
                        let durA = (a["duration"] as? Double) ?? (a["duration"] as? Int).map(Double.init) ?? 0
                        let durB = (b["duration"] as? Double) ?? (b["duration"] as? Int).map(Double.init) ?? 0
                        return abs(durA - prefDur) < abs(durB - prefDur)
                    }
                } else {
                    sortedSynced = syncedItems
                }
                
                for item in sortedSynced {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       let parsed = parseLRCLIBResponse(data: itemData, syncedOnly: syncedOnly) {
                        return parsed
                    }
                }
                
                if !syncedOnly {
                    // Priority 2: Record with plain lyrics from relevant items
                    for item in relevantItems {
                        if let plain = item["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if let itemData = try? JSONSerialization.data(withJSONObject: item),
                               let parsed = parseLRCLIBResponse(data: itemData, syncedOnly: false) {
                                return parsed
                            }
                        }
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
    
    private func isCandidateRelevant(item: [String: Any], preferredTitle: String, preferredArtist: String?) -> Bool {
        guard let trackName = (item["trackName"] as? String)?.lowercased() else { return false }
        let candidateArtist = (item["artistName"] as? String)?.lowercased() ?? ""
        
        let targetTitle = cleanSongTitle(preferredTitle).lowercased()
        let targetArtist = (preferredArtist ?? "").lowercased()
        
        // Exact match
        if trackName == targetTitle {
            return true
        }
        
        // Check for artist match
        let hasArtistMatch: Bool
        if !targetArtist.isEmpty && targetArtist != "youtube music" && targetArtist != "song" {
            let artistTokens = targetArtist.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
            hasArtistMatch = artistTokens.contains { candidateArtist.contains($0) } || candidateArtist.contains(targetArtist)
        } else {
            hasArtistMatch = false
        }
        
        // Extract significant title tokens
        let stopwords: Set<String> = ["the", "and", "from", "with", "for", "you", "song", "audio", "video", "official", "remix", "ost"]
        let titleTokens = targetTitle.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        
        let candidateTokens = Set(trackName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 })
        let overlap = titleTokens.filter { candidateTokens.contains($0) }
        
        if hasArtistMatch {
            return titleTokens.isEmpty || !overlap.isEmpty || trackName.contains(targetTitle) || targetTitle.contains(trackName)
        } else {
            if !titleTokens.isEmpty {
                let ratio = Double(overlap.count) / Double(titleTokens.count)
                if overlap.count >= 2 || ratio >= 0.6 {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - NetEase Cloud Music Provider
    
    public func queryNetEaseLyrics(title: String, artist: String) async -> [LyricLine]? {
        let queryStr = "\(title) \(artist)"
        guard let encoded = queryStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&offset=0&total=true&limit=1") else {
            return nil
        }
        
        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 6.0
        
        do {
            let (sData, sResp) = try await session.data(for: searchReq)
            guard let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
                  let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                  let result = sJson["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]],
                  let firstSong = songs.first,
                  let songId = firstSong["id"] as? Int else {
                return nil
            }
            
            guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(songId)&lv=-1&kv=-1&tv=-1") else {
                return nil
            }
            var lyricReq = URLRequest(url: lyricURL)
            lyricReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            lyricReq.timeoutInterval = 6.0
            
            let (lData, lResp) = try await session.data(for: lyricReq)
            guard let lHttp = lResp as? HTTPURLResponse, lHttp.statusCode == 200,
                  let lJson = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                  let lrcObj = lJson["lrc"] as? [String: Any],
                  let lrcString = lrcObj["lyric"] as? String, !lrcString.isEmpty else {
                return nil
            }
            
            var lines = parseLRC(lrcString)
            guard !lines.isEmpty else { return nil }
            
            // Check for official translation in tlyric
            if let tlyricObj = lJson["tlyric"] as? [String: Any],
               let tlyricString = tlyricObj["lyric"] as? String, !tlyricString.isEmpty {
                let tLines = parseLRC(tlyricString)
                for i in 0..<lines.count {
                    if let matched = tLines.first(where: { abs($0.time - lines[i].time) < 1.2 }) {
                        lines[i].translation = matched.text
                    }
                }
            }
            return lines
        } catch {
            return nil
        }
    }
    
    // MARK: - YouTube Music InnerTube Lyrics Provider
    
    public func queryYouTubeMusicLyrics(videoId: String) async -> [LyricLine]? {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/next") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20240901.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6.0
        
        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240901.01.00",
                    "hl": "en"
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contents = json["contents"] as? [String: Any],
                  let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
                  let tabResults = singleColumn["tabbedRenderer"] as? [String: Any],
                  let watchNextTabs = tabResults["watchNextTabbedResultsRenderer"] as? [String: Any],
                  let tabs = watchNextTabs["tabs"] as? [[String: Any]] else {
                return nil
            }
            
            // Find tab with title "Lyrics"
            var lyricsBrowseId: String? = nil
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let title = tabRenderer["title"] as? String, title.lowercased().contains("lyrics"),
                   let endpoint = tabRenderer["endpoint"] as? [String: Any],
                   let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
                   let browseId = browseEndpoint["browseId"] as? String {
                    lyricsBrowseId = browseId
                    break
                }
            }
            
            guard let bId = lyricsBrowseId else { return nil }
            
            // Call browse endpoint to fetch lyrics text
            guard let browseURL = URL(string: "https://music.youtube.com/youtubei/v1/browse") else { return nil }
            var bRequest = URLRequest(url: browseURL)
            bRequest.httpMethod = "POST"
            bRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            bRequest.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
            bRequest.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
            bRequest.setValue("1.20240901.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
            bRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            bRequest.timeoutInterval = 6.0
            
            let bBody: [String: Any] = [
                "browseId": bId,
                "context": [
                    "client": [
                        "clientName": "WEB_REMIX",
                        "clientVersion": "1.20240901.01.00",
                        "hl": "en"
                    ]
                ]
            ]
            bRequest.httpBody = try? JSONSerialization.data(withJSONObject: bBody)
            
            let (bData, bResp) = try await session.data(for: bRequest)
            guard let bHttp = bResp as? HTTPURLResponse, bHttp.statusCode == 200,
                  let bJson = try? JSONSerialization.jsonObject(with: bData) as? [String: Any],
                  let bContents = bJson["contents"] as? [String: Any],
                  let sectionList = bContents["sectionListRenderer"] as? [String: Any],
                  let sectionContents = sectionList["contents"] as? [[String: Any]],
                  let firstSection = sectionContents.first,
                  let shelf = firstSection["musicDescriptionShelfRenderer"] as? [String: Any],
                  let desc = shelf["description"] as? [String: Any],
                  let runs = desc["runs"] as? [[String: Any]] else {
                return nil
            }
            
            let plainText = runs.compactMap { $0["text"] as? String }.joined()
            let rawLines = plainText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard !rawLines.isEmpty else { return nil }
            return rawLines.map { text in
                LyricLine(time: 0.0, text: text, isSynced: false)
            }
        } catch {
            return nil
        }
    }
    
    // MARK: - Word-by-Word Cadence & Romanization Enrichment
    
    /// Enriches parsed lines with word cadence timings and native phonetic Romanization
    public nonisolated func enrichLines(_ lines: [LyricLine]) -> [LyricLine] {
        var enriched = lines
        let isSynced = lines.first?.isSynced ?? true
        
        for i in 0..<enriched.count {
            let line = enriched[i]
            
            // 1. Calculate word cadence tokens ONLY if line is actually synced
            if isSynced && line.words.isEmpty {
                let nextTime = (i + 1 < enriched.count) ? enriched[i + 1].time : (line.time + 4.5)
                let lineDuration = max(1.2, min(9.0, nextTime - line.time))
                let singDuration = lineDuration * 0.82
                
                let words = line.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if !words.isEmpty {
                    let totalChars = max(1, words.map { $0.count }.reduce(0, +))
                    var runningOffset = 0.0
                    var wordTokens: [LyricWord] = []
                    
                    for w in words {
                        let proportion = Double(w.count) / Double(totalChars)
                        let wDur = max(0.2, singDuration * proportion)
                        wordTokens.append(LyricWord(
                            word: w,
                            time: line.time + runningOffset,
                            duration: wDur
                        ))
                        runningOffset += wDur
                    }
                    enriched[i].words = wordTokens
                }
            }
            
            // 2. Native phonetic Romanization for non-Latin scripts (Romaji / Pinyin / Devanagari)
            if enriched[i].romanization == nil {
                enriched[i].romanization = LRCLIBService.romanize(text: line.text)
            }
        }
        return enriched
    }
    
    // MARK: - Romanization Engine (macOS CoreFoundation Native)
    
    /// Transliterates non-Latin scripts to Latin phonetic characters using macOS Foundation CFStringTransform
    public static func romanize(text: String) -> String? {
        guard !text.isEmpty else { return nil }
        
        // Detect non-Latin Unicode characters
        let hasNonLatin = text.unicodeScalars.contains { scalar in
            scalar.value > 0x024F
        }
        guard hasNonLatin else { return nil }
        
        if let transformed = text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) {
            let trimmed = transformed.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != text && !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
    
    // MARK: - Real-Time AI Translation Engine
    
    /// Translates a collection of lyric lines into target language asynchronously using high-speed chunked batch requests
    public func translateLines(_ lines: [LyricLine], targetLanguage: String = "en") async -> [LyricLine] {
        guard !lines.isEmpty else { return lines }
        var updated = lines
        
        // Find indices that actually need translation
        var indicesToTranslate: [Int] = []
        var textsToTranslate: [String] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.translation == nil && !trimmed.isEmpty {
                indicesToTranslate.append(idx)
                textsToTranslate.append(trimmed)
            }
        }
        
        guard !indicesToTranslate.isEmpty else { return lines }
        
        // Chunk into batches of up to 15 lines to ensure quick responses and stay within limits
        let batchSize = 15
        let totalBatches = Int(ceil(Double(textsToTranslate.count) / Double(batchSize)))
        
        for batchIdx in 0..<totalBatches {
            let start = batchIdx * batchSize
            let end = min(start + batchSize, textsToTranslate.count)
            let batchTexts = Array(textsToTranslate[start..<end])
            let batchIndices = Array(indicesToTranslate[start..<end])
            
            // Join lines with newline character which Google Translate preserves
            let joinedText = batchTexts.joined(separator: "\n")
            if let translatedBatch = await translateBatchText(joinedText, targetLanguage: targetLanguage) {
                let translatedLines = translatedBatch.components(separatedBy: "\n")
                for (offset, lineIdx) in batchIndices.enumerated() {
                    if offset < translatedLines.count {
                        let trans = translatedLines[offset].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trans.isEmpty && trans.lowercased() != batchTexts[offset].lowercased() {
                            updated[lineIdx].translation = trans
                        }
                    }
                }
            }
        }
        
        return updated
    }
    
    /// Batched translation query to Google Translate in a single network round-trip via HTTP POST
    private func translateBatchText(_ text: String, targetLanguage: String = "en") async -> String? {
        guard let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLanguage)&dt=t") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6.0
        
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encodedBody = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = "q=\(encodedBody)".data(using: .utf8)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let segments = array.first as? [[Any]] else { return nil }
            let full = segments.compactMap { $0.first as? String }.joined()
            return full
        } catch {
            return nil
        }
    }
    
    /// Translates a single text string via public Google Translate web API
    public func translateText(_ text: String, targetLanguage: String = "en") async -> String? {
        return await translateBatchText(text, targetLanguage: targetLanguage)
    }
    
    // MARK: - Song Story & Meaning (Music DNA)
    
    /// Searches Wikipedia API (Action search + REST Summary) with multi-language fallback
    private func searchWikipedia(query: String, lang: String = "en") async -> (title: String, extract: String, desc: String?)? {
        let clean = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let searchURL = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(clean)&utf8=1&format=json&srlimit=1") else {
            return nil
        }
        var req = URLRequest(url: searchURL)
        req.setValue("Sonorist/2.0 (macOS; Native Music App)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 5.0
        
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let qObj = json["query"] as? [String: Any],
              let searchArr = qObj["search"] as? [[String: Any]],
              let first = searchArr.first,
              let pageTitle = first["title"] as? String, !pageTitle.isEmpty else {
            return nil
        }
        
        // Fetch summary for the discovered page title
        guard let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let summaryURL = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            return nil
        }
        var sumReq = URLRequest(url: summaryURL)
        sumReq.setValue("Sonorist/2.0 (macOS; Native Music App)", forHTTPHeaderField: "User-Agent")
        sumReq.timeoutInterval = 5.0
        
        guard let (sData, sResp) = try? await session.data(for: sumReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let extract = sJson["extract"] as? String, !extract.isEmpty else {
            return nil
        }
        
        let desc = sJson["description"] as? String
        return (title: pageTitle, extract: extract, desc: desc)
    }
    
    private func detectScriptLanguage(_ text: String) -> String? {
        for scalar in text.unicodeScalars {
            // Bengali: 0x0980 - 0x09FF
            if scalar.value >= 0x0980 && scalar.value <= 0x09FF { return "bn" }
            // Devanagari (Hindi): 0x0900 - 0x097F
            if scalar.value >= 0x0900 && scalar.value <= 0x097F { return "hi" }
            // Japanese (Hiragana/Katakana): 0x3040 - 0x30FF
            if scalar.value >= 0x3040 && scalar.value <= 0x30FF { return "ja" }
            // Chinese: 0x4E00 - 0x9FFF
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF { return "zh" }
        }
        return nil
    }
    
    private func parseCreditsFromDescription(_ desc: String, track: Track) -> TrackStory? {
        var composer: String? = nil
        var lyricist: String? = nil
        var label: String? = nil
        var movieOrAlbum: String? = nil
        var year: String? = nil
        
        let lines = desc.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        for line in lines {
            if line.lowercased().hasPrefix("provided to youtube by ") {
                label = line.replacingOccurrences(of: "Provided to YouTube by ", with: "", options: .caseInsensitive)
            } else if line.contains("℗") {
                let parts = line.replacingOccurrences(of: "℗", with: "").trimmingCharacters(in: .whitespaces)
                let tokens = parts.components(separatedBy: .whitespaces)
                if let firstNum = tokens.first(where: { $0.count == 4 && Int($0) != nil }) {
                    year = firstNum
                }
                if label == nil {
                    label = parts
                }
            } else if line.lowercased().hasPrefix("composer:") {
                composer = line.replacingOccurrences(of: "Composer:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("lyricist:") || line.lowercased().hasPrefix("author:") {
                lyricist = line.replacingOccurrences(of: "Lyricist:", with: "", options: .caseInsensitive)
                               .replacingOccurrences(of: "Author:", with: "", options: .caseInsensitive)
                               .trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("released on:") {
                let rel = line.replacingOccurrences(of: "Released on:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                if let y = rel.split(separator: "-").first, y.count == 4 {
                    year = String(y)
                }
            }
        }
        
        // Find album or movie line (usually the line right after Title · Artist)
        if lines.count >= 3 {
            for i in 0..<lines.count - 1 {
                if lines[i].contains("·") {
                    let nextCandidate = lines[i+1]
                    if !nextCandidate.hasPrefix("℗") && !nextCandidate.hasPrefix("Auto-generated") {
                        movieOrAlbum = nextCandidate
                    }
                    break
                }
            }
        }
        
        guard composer != nil || lyricist != nil || label != nil || movieOrAlbum != nil else {
            return nil
        }
        
        var storyParts: [String] = []
        if let movieOrAlbum = movieOrAlbum {
            if let y = year {
                storyParts.append("Featured in \"\(movieOrAlbum)\" (\(y)).")
            } else {
                storyParts.append("Featured in \"\(movieOrAlbum)\".")
            }
        } else if let year = year {
            storyParts.append("Released in \(year).")
        }
        
        var creditParts: [String] = []
        if let composer = composer, let lyricist = lyricist, composer == lyricist {
            creditParts.append("Composed and written by \(composer)")
        } else {
            if let composer = composer {
                creditParts.append("Composed by \(composer)")
            }
            if let lyricist = lyricist {
                creditParts.append("penned by \(lyricist)")
            }
        }
        if !creditParts.isEmpty {
            storyParts.append("\(creditParts.joined(separator: ", ")), performed by \(track.artist).")
        }
        if let label = label {
            storyParts.append("Released under \(label).")
        }
        
        let summaryLine = [movieOrAlbum, year, label].compactMap { $0 }.joined(separator: " • ")
        return TrackStory(
            title: track.title,
            artist: track.artist,
            summary: summaryLine.isEmpty ? "\(track.artist) • Track Story" : summaryLine,
            source: label ?? "Official YouTube Credits",
            releaseYear: year ?? track.album,
            genre: movieOrAlbum != nil ? "Film Soundtrack" : "Single",
            extract: storyParts.joined(separator: " ")
        )
    }
    
    /// Fetches track backstory, meaning, and trivia via YouTube official credits, Wikipedia, and verified metadata
    public func fetchTrackStory(for track: Track) async -> TrackStory? {
        let cleanTitle = cleanSongTitle(track.title)
        let cleanArtist = cleanArtistName(track.artist)
        
        // 1. YouTube Official Credits from InnerTube
        if let desc = await InnerTubeClient.shared.fetchTrackDescription(videoId: track.id),
           let creditsStory = parseCreditsFromDescription(desc, track: track) {
            // Also enrich with Wikipedia artist bio if available
            if let wiki = await searchWikipedia(query: cleanArtist), !wiki.extract.isEmpty {
                let combined = "\(creditsStory.extract) \(wiki.extract)"
                return TrackStory(
                    title: track.title,
                    artist: track.artist,
                    summary: creditsStory.summary,
                    source: "\(creditsStory.source) • Wikipedia",
                    releaseYear: creditsStory.releaseYear,
                    genre: creditsStory.genre,
                    extract: combined
                )
            }
            return creditsStory
        }
        
        // 2. Wikipedia search with song title + artist
        let queries = [
            "\(cleanTitle) \(cleanArtist)",
            "\(cleanTitle) (song)",
            cleanTitle,
            cleanArtist
        ]
        
        for q in queries {
            if let wiki = await searchWikipedia(query: q) {
                return TrackStory(
                    title: track.title,
                    artist: track.artist,
                    summary: wiki.desc ?? "\(track.artist) • \(cleanTitle)",
                    source: "Wikipedia",
                    releaseYear: track.album,
                    genre: nil,
                    extract: wiki.extract
                )
            }
        }
        
        // 3. Regional Wikipedia fallback
        if let lang = detectScriptLanguage(cleanTitle + cleanArtist),
           let wiki = await searchWikipedia(query: "\(cleanTitle) \(cleanArtist)", lang: lang) {
            return TrackStory(
                title: track.title,
                artist: track.artist,
                summary: wiki.desc ?? "\(track.artist) • \(cleanTitle)",
                source: "Wikipedia (\(lang.uppercased()))",
                releaseYear: track.album,
                genre: nil,
                extract: wiki.extract
            )
        }
        
        // 4. High-Fidelity Musical Profile
        let albumText = track.album.map { " from the album \"\($0)\"" } ?? ""
        let durationText = track.durationSeconds > 0 ? " with a runtime of \(track.formattedDuration)" : ""
        let summaryText = track.album.map { "\(track.artist) • \($0)" } ?? track.artist
        return TrackStory(
            title: track.title,
            artist: track.artist,
            summary: summaryText,
            source: "Verified Track Metadata",
            releaseYear: track.album,
            genre: track.audioFormat,
            extract: "\"\(track.title)\" is a musical work performed by \(track.artist)\(albumText)\(durationText). Recorded and delivered in high-fidelity audio."
        )
    }
    
    // MARK: - Parsing
    
    private func parseLRCLIBResponse(data: Data, syncedOnly: Bool = false) -> [LyricLine]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Prefer syncedLyrics
        if let synced = json["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = parseLRC(synced)
            if !parsed.isEmpty {
                return parsed
            }
        }
        
        if syncedOnly {
            return nil
        }
        
        // Fallback to plainLyrics only when syncedOnly is false
        if let plain = json["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.map { text in
                LyricLine(time: 0.0, text: text, isSynced: false)
            }
        }
        
        return nil
    }
    
    /// Parses LRC standard timestamp strings: `[mm:ss.xx] Line content`
    /// Supports `[offset: +/-ms]` tags, multi-timestamp lines, and flexible minute/second formatting
    public nonisolated func parseLRC(_ lrcString: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = lrcString.components(separatedBy: .newlines)
        
        // 1. Parse optional standard LRC global [offset: +/-ms] tag
        var globalOffsetSeconds: Double = 0.0
        let offsetPattern = #"\[offset:\s*([+-]?\d+)\s*\]"#
        if let offsetRegex = try? NSRegularExpression(pattern: offsetPattern, options: .caseInsensitive) {
            let fullRange = NSRange(location: 0, length: lrcString.utf16.count)
            if let match = offsetRegex.firstMatch(in: lrcString, options: [], range: fullRange),
               let numRange = Range(match.range(at: 1), in: lrcString),
               let offsetMs = Double(lrcString[numRange]) {
                globalOffsetSeconds = offsetMs / 1000.0
            }
        }
        
        // 2. Regex matches timestamp tags: [01:23.45], [1:23.45], [01:23.456], or [01:23]
        let timeTagPattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let timeTagRegex = try? NSRegularExpression(pattern: timeTagPattern) else {
            return []
        }
        
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Skip non-lyric metadata headers like [ar: ...], [ti: ...], [offset: ...]
            if trimmed.hasPrefix("[offset:") || trimmed.hasPrefix("[ar:") || trimmed.hasPrefix("[ti:") || trimmed.hasPrefix("[al:") || trimmed.hasPrefix("[by:") {
                continue
            }
            
            let nsRange = NSRange(location: 0, length: trimmed.utf16.count)
            let matches = timeTagRegex.matches(in: trimmed, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }
            
            // Extract the lyric text (after stripping out all [mm:ss.xx] tags)
            let text = timeTagRegex.stringByReplacingMatches(in: trimmed, options: [], range: nsRange, withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            
            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: trimmed),
                      let secRange = Range(match.range(at: 2), in: trimmed),
                      let mins = Double(trimmed[minRange]),
                      let secs = Double(trimmed[secRange]) else { continue }
                
                var subSeconds: Double = 0.0
                if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound,
                   let subRange = Range(match.range(at: 3), in: trimmed),
                   let subVal = Double(trimmed[subRange]) {
                    let divisor = (match.range(at: 3).length == 3) ? 1000.0 : 100.0
                    subSeconds = subVal / divisor
                }
                
                let totalSeconds = (mins * 60.0) + secs + subSeconds + globalOffsetSeconds
                lines.append(LyricLine(time: max(0, totalSeconds), text: text, isSynced: true))
            }
        }
        
        return lines.sorted(by: { $0.time < $1.time })
    }
    
    // MARK: - Cleaning Helpers
    
    private func cleanSongTitle(_ title: String) -> String {
        var cleaned = title
        let patterns = [
            #"\(Official (Music )?Video\)"#,
            #"\(Music Video\)"#,
            #"\[Music Video\]"#,
            #"\(Official Audio\)"#,
            #"\[Official (Music )?Video\]"#,
            #"\[Official Audio\]"#,
            #"\[Audio\]"#,
            #"\(Audio Track\)"#,
            #"\(Lyric Video\)"#,
            #"\[Lyric Video\]"#,
            #"\(Official Lyric Video\)"#,
            #"\[Official Lyric Video\]"#,
            #"\(Lyrics\)"#,
            #"\[Lyrics\]"#,
            #"\(Visualizer( Video)?\)"#,
            #"\[Visualizer\]"#,
            #"\(Audio\)"#,
            #"\(Remastered( [0-9]{4})?\)"#,
            #"\[Remastered( [0-9]{4})?\]"#,
            #"\(Live( [^\)]+)?\)"#,
            #"\[Live( [^\]]+)?\]"#,
            #"\[HQ\]"#,
            #"\[HD\]"#,
            #"\(feat\.[^\)]+\)"#,
            #"\(ft\.[^\)]+\)"#,
            #"\((From|from|FROM)[^\)]+\)"#,
            #"\[(From|from|FROM)[^\]]+\]"#,
            #"\((OST|Soundtrack)[^\)]*\)"#,
            #"\[(OST|Soundtrack)[^\]]*\]"#,
            #"\| Official Video"#
        ]
        for pat in patterns {
            if let reg = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = reg.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanArtistName(_ artist: String) -> String {
        var cleaned = artist
            .replacingOccurrences(of: " - Topic", with: "")
            .replacingOccurrences(of: "VEVO", with: "")
            .replacingOccurrences(of: "Official", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix(" -") {
            cleaned = String(cleaned.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
    
    // MARK: - Disk Cache
    
    private func loadCachedLyrics(for trackId: String) -> [LyricLine]? {
        let safeId = trackId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeId.isEmpty else { return nil }
        let file = lyricsCacheDir.appendingPathComponent("\(safeId).json")
        guard let data = try? Data(contentsOf: file),
              let lines = try? JSONDecoder().decode([LyricLine].self, from: data) else {
            return nil
        }
        return lines
    }
    
    private func saveCachedLyrics(_ lines: [LyricLine], for trackId: String) {
        let safeId = trackId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeId.isEmpty else { return }
        let file = lyricsCacheDir.appendingPathComponent("\(safeId).json")
        if let data = try? JSONEncoder().encode(lines) {
            try? data.write(to: file, options: .atomic)
        }
    }
    
    public func clearLyricsCache() {
        try? fileManager.removeItem(at: lyricsCacheDir)
        try? fileManager.createDirectory(at: lyricsCacheDir, withIntermediateDirectories: true)
    }
}
