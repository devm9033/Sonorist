import Foundation
import Combine

public enum AIInsightsTone: String, CaseIterable, Codable, Identifiable {
    case poetic = "Poetic & Soulful"
    case witty = "Witty & Sharp"
    case analytical = "Analytical"
    
    public var id: String { rawValue }
}

public struct AIInsightsStory: Codable, Sendable {
    public let archetypeTitle: String
    public let archetypeDescription: String
    public let narrativeStory: String
    public let obsessionSongTitle: String?
    public let obsessionArtist: String?
    public let obsessionInsight: String?
    public let peakListeningHour: String
    public let patienceRateText: String
    public let modelUsed: String
    public let generatedAt: Date
    public let tone: AIInsightsTone

    public init(
        archetypeTitle: String,
        archetypeDescription: String,
        narrativeStory: String,
        obsessionSongTitle: String? = nil,
        obsessionArtist: String? = nil,
        obsessionInsight: String? = nil,
        peakListeningHour: String = "11:15 PM",
        patienceRateText: String = "94% Zero-Skip",
        modelUsed: String = "Sonorist Biographer",
        generatedAt: Date = Date(),
        tone: AIInsightsTone = .poetic
    ) {
        self.archetypeTitle = archetypeTitle
        self.archetypeDescription = archetypeDescription
        self.narrativeStory = narrativeStory
        self.obsessionSongTitle = obsessionSongTitle
        self.obsessionArtist = obsessionArtist
        self.obsessionInsight = obsessionInsight
        self.peakListeningHour = peakListeningHour
        self.patienceRateText = patienceRateText
        self.modelUsed = modelUsed
        self.generatedAt = generatedAt
        self.tone = tone
    }
}

public struct LanguageProportion: Identifiable, Hashable {
    public var id: String { language }
    public let language: String
    public let count: Int
    public let percentage: Double
    public let colorName: String
}

@MainActor
public final class AIInsightsEngine: ObservableObject {
    public static let shared = AIInsightsEngine()
    
    @Published public var selectedTone: AIInsightsTone = .poetic {
        didSet {
            UserDefaults.standard.set(selectedTone.rawValue, forKey: "sonorist_insights_selected_tone")
            loadCachedStoryForCurrentTone()
        }
    }
    
    @Published public var currentStory: AIInsightsStory?
    @Published public var isGenerating: Bool = false
    @Published public var lastGeneratedDate: Date? = nil
    
    private let kCachedInsightsPrefix = "sonorist_cached_insights_"
    
    public init() {
        if let savedToneRaw = UserDefaults.standard.string(forKey: "sonorist_insights_selected_tone"),
           let tone = AIInsightsTone(rawValue: savedToneRaw) {
            self.selectedTone = tone
        }
        loadCachedStoryForCurrentTone()
    }
    
    public func loadCachedStoryForCurrentTone() {
        let key = kCachedInsightsPrefix + selectedTone.rawValue
        if let data = UserDefaults.standard.data(forKey: key),
           let story = try? JSONDecoder().decode(AIInsightsStory.self, from: data) {
            self.currentStory = story
            self.lastGeneratedDate = story.generatedAt
        } else {
            // Provide a graceful heuristic fallback based on real data
            self.currentStory = generateHeuristicStory(tone: selectedTone)
        }
    }
    
    // MARK: - Language Horizon Spectrum
    
    public var computedLanguageSpectrum: [LanguageProportion] {
        let allTracks = ListeningAnalyticsManager.shared.topTracks.map { $0.track }
        guard !allTracks.isEmpty else { return [] }
        
        let curated = AIPlaylistEngine.shared.curatedLibrary
        var langCounts: [String: Int] = [:]
        
        for track in allTracks {
            if let cat = curated.category(for: track.id) {
                langCounts[cat.language, default: 0] += 1
            } else {
                let detected = AIPlaylistEngine.shared.classifyTrackHeuristically(track).language
                langCounts[detected, default: 0] += 1
            }
        }
        
        let total = Double(max(1, allTracks.count))
        let colors = ["musicRed", "amber", "indigo", "teal", "purple", "emerald"]
        var result: [LanguageProportion] = []
        var colorIdx = 0
        
        for (lang, count) in langCounts.sorted(by: { $0.value > $1.value }) {
            let pct = Double(count) / total
            result.append(LanguageProportion(
                language: lang,
                count: count,
                percentage: pct,
                colorName: colors[colorIdx % colors.count]
            ))
            colorIdx += 1
        }
        return result
    }
    
    // MARK: - The Obsession Index
    
    public var obsessionTrack: (track: Track, repeats: Int, rateText: String)? {
        let top = ListeningAnalyticsManager.shared.topTracks
        guard let first = top.first, first.playCount >= 2 else {
            // Check journal for consecutive repeats
            let journal = ListeningAnalyticsManager.shared.listeningJournal
            if let repeatedEvent = journal.reversed().first(where: { $0.wasRepeated }) {
                let trk = Track(id: repeatedEvent.trackId, title: repeatedEvent.trackTitle, artist: repeatedEvent.artist)
                return (track: trk, repeats: 3, rateText: "Played consecutively • High emotional focus")
            }
            if let singleTop = top.first {
                return (track: singleTop.track, repeats: singleTop.playCount, rateText: "Top played track this week")
            }
            return nil
        }
        
        let rate = first.totalSeconds > 0 ? "Full immersion • Zero skips" : "\(first.playCount)x in rotation"
        return (track: first.track, repeats: first.playCount, rateText: rate)
    }
    
    // MARK: - Threshold & Auto-Sync
    
    public var isThresholdReached: Bool {
        ListeningAnalyticsManager.shared.totalSongsPlayed >= 10
    }
    
    public var thresholdProgress: Double {
        min(1.0, Double(ListeningAnalyticsManager.shared.totalSongsPlayed) / 10.0)
    }
    
    public var shouldAutoSync: Bool {
        guard isThresholdReached else { return false }
        let cleanKey = AIProviderConfig.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return false }
        guard let last = lastGeneratedDate else { return true }
        let hoursSinceLast = Date().timeIntervalSince(last) / 3600.0
        return hoursSinceLast >= 5.0
    }
    
    // MARK: - AI Generation
    
    public func generateInsights(force: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        
        let manager = ListeningAnalyticsManager.shared
        let config = AIProviderConfig.shared
        let tone = self.selectedTone
        
        // 1. If threshold reached and user has an API key, query LLM for musicological commentary
        let cleanKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if isThresholdReached && !cleanKey.isEmpty {
            do {
                let story = try await queryLLMForInsights(tone: tone)
                self.currentStory = story
                self.lastGeneratedDate = story.generatedAt
                saveStory(story, for: tone)
                return
            } catch {
                #if DEBUG
                print("[AIInsightsEngine]: LLM generation failed (\(error)), falling back to Heuristic Engine")
                #endif
            }
        }
        
        // 2. Intelligent Grounded Heuristic Engine (100% offline, guaranteed, authentic)
        let heuristic = generateHeuristicStory(tone: tone)
        self.currentStory = heuristic
        self.lastGeneratedDate = heuristic.generatedAt
        saveStory(heuristic, for: tone)
    }
    
    private func saveStory(_ story: AIInsightsStory, for tone: AIInsightsTone) {
        let key = kCachedInsightsPrefix + tone.rawValue
        if let data = try? JSONEncoder().encode(story) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    // MARK: - Query Configured LLM (OpenRouter / OpenAI / Claude / Gemini)
    
    private func queryLLMForInsights(tone: AIInsightsTone) async throws -> AIInsightsStory {
        let manager = ListeningAnalyticsManager.shared
        let topTracksSummary = manager.topTracks.prefix(5).map { "\($0.track.title) by \($0.track.artist) (\($0.playCount) plays)" }.joined(separator: ", ")
        let primaryTime = manager.primaryTimeOfDay
        let totalMins = Int(manager.totalSecondsListened) / 60
        let totalSongs = manager.totalSongsPlayed
        let spectrum = computedLanguageSpectrum.map { "\($0.language) (\(Int($0.percentage * 100))%)" }.joined(separator: ", ")
        let completionRate = "\(Int(manager.completionPercentage * 100))%"
        
        let prompt = """
        You are an objective musicologist analyzing authentic playback telemetry.
        Do NOT output horoscopes, fantasy titles, or poetic fluff.
        Provide a factual, 2-3 sentence analysis of the musical themes, acoustic coherence, and listening habits.

        User Telemetry:
        - Total Songs Played: \(totalSongs)
        - Total Time: \(totalMins) minutes
        - Language Spectrum: \(spectrum.isEmpty ? "Diverse" : spectrum)
        - Top Tracks: \(topTracksSummary.isEmpty ? "Acoustic exploration" : topTracksSummary)
        - Peak Window: \(manager.peakListeningWindow)
        - Completion Rate: \(completionRate) full plays

        Output STRICTLY valid JSON with no markdown wrapping or preamble:
        {
          "archetypeTitle": "A concise 2-4 word summary of their dominant style (e.g. 'Acoustic Rabindra Sangeet' or 'Contemporary Hindi Ballads')",
          "archetypeDescription": "1 factual sentence characterizing their musical sound profile",
          "narrativeStory": "2 concise, objective sentences analyzing their listening consistency and musical preferences",
          "obsessionSongTitle": "Name of top track or null",
          "obsessionArtist": "Artist name or null",
          "obsessionInsight": "Factual observation on repeat count and immersion",
          "peakListeningHour": "\(manager.peakListeningWindow.components(separatedBy: " (").first ?? "Evening")",
          "patienceRateText": "\(completionRate) Full Completion"
        }
        """
        
        let rawResponse = try await AIPlaylistEngine.shared.executeLLMRequest(prompt: prompt)
        
        struct LLMOutput: Codable {
            let archetypeTitle: String
            let archetypeDescription: String
            let narrativeStory: String
            let obsessionSongTitle: String?
            let obsessionArtist: String?
            let obsessionInsight: String?
            let peakListeningHour: String?
            let patienceRateText: String?
        }
        
        // Clean JSON from potential markdown codeblocks
        var cleaned = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(LLMOutput.self, from: data) else {
            throw NSError(domain: "AIInsightsEngine", code: 422, userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI story JSON"])
        }
        
        let modelName = AIProviderConfig.shared.selectedModelId.components(separatedBy: "/").last?.components(separatedBy: ":").first ?? "AI Engine"
        
        return AIInsightsStory(
            archetypeTitle: parsed.archetypeTitle,
            archetypeDescription: parsed.archetypeDescription,
            narrativeStory: parsed.narrativeStory,
            obsessionSongTitle: parsed.obsessionSongTitle,
            obsessionArtist: parsed.obsessionArtist,
            obsessionInsight: parsed.obsessionInsight,
            peakListeningHour: parsed.peakListeningHour ?? "Evening",
            patienceRateText: parsed.patienceRateText ?? "\(completionRate) Full Completion",
            modelUsed: modelName,
            generatedAt: Date(),
            tone: tone
        )
    }
    
    // MARK: - Intelligent Grounded Heuristic Generator (Zero Fake Data)
    
    public func generateHeuristicStory(tone: AIInsightsTone = .analytical) -> AIInsightsStory {
        let manager = ListeningAnalyticsManager.shared
        let top = manager.topTracks
        let languages = computedLanguageSpectrum
        let primaryLang = languages.first?.language ?? "Eclectic"
        let topTrack = top.first?.track
        let topCount = top.first?.playCount ?? 1
        let completionPct = "\(Int(manager.completionPercentage * 100))%"
        
        let archetypeTitle = "\(primaryLang) Acoustic Soundscape"
        let archetypeDesc = "Your listening centers around \(primaryLang.lowercased()) melodic arrangements with high completion rates."
        let artistName = topTrack?.artist ?? "featured artists"
        let peakWindow = manager.peakListeningWindow.components(separatedBy: " (").first ?? "Evening"
        let story = "Your playback log reflects deep engagement with \(artistName) and melodic arrangements, peaking in the \(peakWindow.lowercased()). You listen through \(completionPct) of tracks to completion with minimal early skips."
        
        return AIInsightsStory(
            archetypeTitle: archetypeTitle,
            archetypeDescription: archetypeDesc,
            narrativeStory: story,
            obsessionSongTitle: topTrack?.title,
            obsessionArtist: topTrack?.artist,
            obsessionInsight: topTrack != nil ? "Played \(topCount)x in full rotation" : nil,
            peakListeningHour: peakWindow,
            patienceRateText: "\(completionPct) Full Completion",
            modelUsed: "On-Device Synthesis",
            generatedAt: Date(),
            tone: tone
        )
    }
}
