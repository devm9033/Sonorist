import Foundation
import Combine

public struct TrackAnalytics: Identifiable, Equatable, Codable, Sendable {
    public var id: String { track.id }
    public let track: Track
    public var playCount: Int
    public var totalSeconds: Double
    
    public init(track: Track, playCount: Int, totalSeconds: Double) {
        self.track = track
        self.playCount = playCount
        self.totalSeconds = totalSeconds
    }
}

public struct ListeningEvent: Identifiable, Codable, Sendable {
    public var id: UUID
    public let trackId: String
    public let trackTitle: String
    public let artist: String
    public let language: String?
    public let timestamp: Date
    public let secondsPlayed: Double
    public let trackDuration: Double
    public let completedFullSong: Bool
    public let wasSkippedEarly: Bool
    public let wasRepeated: Bool
    public let audioFormat: String
    
    public init(
        id: UUID = UUID(),
        trackId: String,
        trackTitle: String,
        artist: String,
        language: String? = nil,
        timestamp: Date = Date(),
        secondsPlayed: Double,
        trackDuration: Double,
        completedFullSong: Bool,
        wasSkippedEarly: Bool,
        wasRepeated: Bool,
        audioFormat: String
    ) {
        self.id = id
        self.trackId = trackId
        self.trackTitle = trackTitle
        self.artist = artist
        self.language = language
        self.timestamp = timestamp
        self.secondsPlayed = secondsPlayed
        self.trackDuration = trackDuration
        self.completedFullSong = completedFullSong
        self.wasSkippedEarly = wasSkippedEarly
        self.wasRepeated = wasRepeated
        self.audioFormat = audioFormat
    }
}

public enum TimeOfDaySlot: String, CaseIterable, Identifiable, Codable {
    case morning = "Morning (6 AM - 12 PM)"
    case afternoon = "Afternoon (12 PM - 5 PM)"
    case evening = "Evening (5 PM - 10 PM)"
    case night = "Night (10 PM - 6 AM)"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .morning: return "sun.horizon.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

@MainActor
public final class ListeningAnalyticsManager: ObservableObject {
    public static let shared = ListeningAnalyticsManager()
    
    @Published public var totalSecondsListened: Double = 0
    @Published public var totalSongsPlayed: Int = 0
    @Published public var topTracks: [TrackAnalytics] = []
    @Published public var topArtists: [(artist: String, count: Int, percentage: Double)] = []
    @Published public var formatDistribution: [String: Int] = [
        "CoreAudio AAC (128k)": 0,
        "High-Fidelity Opus (160k)": 0,
        "Offline Cached": 0
    ]
    @Published public var timeSlotDistribution: [TimeOfDaySlot: Int] = [
        .morning: 0,
        .afternoon: 0,
        .evening: 0,
        .night: 0
    ]
    @Published public var currentStreakDays: Int = 0
    @Published public var listeningJournal: [ListeningEvent] = []
    @Published public var lastListeningDate: Date? = nil
    
    private let userDefaults = UserDefaults.standard
    private let kTotalSeconds = "sonorist_analytics_total_seconds"
    private let kTotalSongs = "sonorist_analytics_total_songs"
    private let kTopTracks = "sonorist_analytics_top_tracks_v2"
    private let kFormatDist = "sonorist_analytics_format_dist_v2"
    private let kTimeSlotDist = "sonorist_analytics_timeslot_dist_v2"
    private let kJournal = "sonorist_analytics_journal_v2"
    private let kStreakDays = "sonorist_analytics_streak_days_v2"
    private let kLastListeningDate = "sonorist_analytics_last_date_v2"
    
    // Performance Optimization: Batched persistence
    private var unpersistedSeconds: Double = 0.0
    private var unnotifiedSeconds: Double = 0.0
    
    public init() {
        loadPersistedStats()
    }
    
    // MARK: - Tracking
    
    public func recordTrackStart(track: Track, quality: AudioQuality, isCached: Bool) {
        totalSongsPlayed += 1
        userDefaults.set(totalSongsPlayed, forKey: kTotalSongs)
        
        // Format breakdown
        if isCached {
            formatDistribution["Offline Cached", default: 0] += 1
        } else {
            switch quality {
            case .standard:
                formatDistribution["CoreAudio AAC (128k)", default: 0] += 1
            case .high:
                formatDistribution["High-Fidelity Opus (160k)", default: 0] += 1
            case .auto:
                formatDistribution["Adaptive Auto Stream", default: 0] += 1
            case .dataSaver:
                formatDistribution["Data Saver (AAC 48k)", default: 0] += 1
            }
        }
        
        // Time slot breakdown
        let slot = currentSlot()
        timeSlotDistribution[slot, default: 0] += 1
        
        // Track play counts
        if let idx = topTracks.firstIndex(where: { $0.track.id == track.id }) {
            topTracks[idx].playCount += 1
        } else {
            topTracks.append(TrackAnalytics(track: track, playCount: 1, totalSeconds: 0))
        }
        topTracks.sort { $0.playCount > $1.playCount }
        
        recalculateArtists()
        flushPersistedStats()
    }
    
    public func recordListeningTime(seconds: Double, track: Track?) {
        guard seconds > 0 else { return }
        unnotifiedSeconds += seconds
        unpersistedSeconds += seconds
        
        if let track = track, let idx = topTracks.firstIndex(where: { $0.track.id == track.id }) {
            topTracks[idx].totalSeconds += seconds
        }
        
        // Throttled notification: Only trigger @Published change every 5 seconds of listening
        if unnotifiedSeconds >= 5.0 {
            totalSecondsListened += unnotifiedSeconds
            unnotifiedSeconds = 0.0
        }
        
        // Batched disk writes: Only write to UserDefaults every 15 seconds of continuous playback
        if unpersistedSeconds >= 15.0 {
            flushPersistedStats()
        }
    }
    
    public func recordListeningEvent(
        track: Track,
        secondsPlayed: Double,
        totalDuration: Double,
        wasSkipped: Bool,
        wasRepeated: Bool,
        audioFormat: String,
        language: String? = nil
    ) {
        let isFull = secondsPlayed >= max(30.0, totalDuration * 0.8)
        let isEarlySkip = wasSkipped && secondsPlayed < 15.0
        
        let event = ListeningEvent(
            trackId: track.id,
            trackTitle: track.title,
            artist: track.artist,
            language: language,
            timestamp: Date(),
            secondsPlayed: secondsPlayed,
            trackDuration: totalDuration,
            completedFullSong: isFull,
            wasSkippedEarly: isEarlySkip,
            wasRepeated: wasRepeated,
            audioFormat: audioFormat
        )
        
        listeningJournal.append(event)
        
        // Dynamic Rolling Cap: Allows up to ~1 MB of rich logs without exceeding
        if listeningJournal.count > 3000 {
            listeningJournal.removeFirst(listeningJournal.count - 3000)
        }
        
        if let data = try? JSONEncoder().encode(listeningJournal) {
            if data.count > 950_000 {
                // Safely prune oldest logs if serialized size exceeds 950 KB to stay strictly under 1 MB
                let pruneCount = max(50, listeningJournal.count / 4)
                listeningJournal.removeFirst(min(pruneCount, listeningJournal.count))
                if let trimmedData = try? JSONEncoder().encode(listeningJournal) {
                    userDefaults.set(trimmedData, forKey: kJournal)
                }
            } else {
                userDefaults.set(data, forKey: kJournal)
            }
        }
        
        // Ensure topTracks captures the listening duration
        if let idx = topTracks.firstIndex(where: { $0.track.id == track.id }) {
            topTracks[idx].totalSeconds += secondsPlayed
            if wasRepeated {
                topTracks[idx].playCount += 1
            }
        } else {
            topTracks.append(TrackAnalytics(track: track, playCount: 1, totalSeconds: secondsPlayed))
        }
        topTracks.sort { $0.playCount > $1.playCount }
        recalculateArtists()
        
        updateStreak()
        flushPersistedStats()
    }
    
    private func updateStreak() {
        let now = Date()
        let calendar = Calendar.current
        if let last = lastListeningDate {
            if calendar.isDateInToday(last) {
                return
            } else if calendar.isDateInYesterday(last) {
                currentStreakDays += 1
            } else {
                currentStreakDays = 1
            }
        } else {
            currentStreakDays = 1
        }
        lastListeningDate = now
        userDefaults.set(currentStreakDays, forKey: kStreakDays)
        userDefaults.set(now.timeIntervalSince1970, forKey: kLastListeningDate)
    }
    
    public func flushPersistedStats() {
        if unnotifiedSeconds > 0 {
            totalSecondsListened += unnotifiedSeconds
            unnotifiedSeconds = 0.0
        }
        userDefaults.set(totalSecondsListened, forKey: kTotalSeconds)
        userDefaults.set(totalSongsPlayed, forKey: kTotalSongs)
        unpersistedSeconds = 0.0
        
        // Persist topTracks
        if let data = try? JSONEncoder().encode(topTracks) {
            userDefaults.set(data, forKey: kTopTracks)
        }
        
        // Persist format and time distribution
        userDefaults.set(formatDistribution, forKey: kFormatDist)
        var rawSlots: [String: Int] = [:]
        for (slot, count) in timeSlotDistribution {
            rawSlots[slot.rawValue] = count
        }
        userDefaults.set(rawSlots, forKey: kTimeSlotDist)
    }
    
    public func resetAll() {
        totalSecondsListened = 0
        totalSongsPlayed = 0
        currentStreakDays = 0
        lastListeningDate = nil
        unpersistedSeconds = 0.0
        unnotifiedSeconds = 0.0
        topTracks.removeAll()
        topArtists.removeAll()
        listeningJournal.removeAll()
        formatDistribution = [
            "CoreAudio AAC (128k)": 0,
            "High-Fidelity Opus (160k)": 0,
            "Offline Cached": 0
        ]
        timeSlotDistribution = [
            .morning: 0,
            .afternoon: 0,
            .evening: 0,
            .night: 0
        ]
        userDefaults.removeObject(forKey: kTotalSeconds)
        userDefaults.removeObject(forKey: kTotalSongs)
        userDefaults.removeObject(forKey: kTopTracks)
        userDefaults.removeObject(forKey: kFormatDist)
        userDefaults.removeObject(forKey: kTimeSlotDist)
        userDefaults.removeObject(forKey: kJournal)
        userDefaults.removeObject(forKey: kStreakDays)
        userDefaults.removeObject(forKey: kLastListeningDate)
    }
    
    public func restoreFromBackup(
        totalSeconds: Double,
        totalSongs: Int,
        streakDays: Int,
        topTracks: [TrackAnalytics],
        journal: [ListeningEvent],
        formatDist: [String: Int],
        timeSlotDist: [TimeOfDaySlot: Int]
    ) {
        self.totalSecondsListened = totalSeconds
        self.totalSongsPlayed = totalSongs
        self.currentStreakDays = streakDays
        self.topTracks = topTracks
        self.listeningJournal = journal
        self.formatDistribution = formatDist
        self.timeSlotDistribution = timeSlotDist
        
        userDefaults.set(totalSeconds, forKey: kTotalSeconds)
        userDefaults.set(totalSongs, forKey: kTotalSongs)
        userDefaults.set(streakDays, forKey: kStreakDays)
        
        if let data = try? JSONEncoder().encode(topTracks) {
            userDefaults.set(data, forKey: kTopTracks)
        }
        if let data = try? JSONEncoder().encode(journal) {
            userDefaults.set(data, forKey: kJournal)
        }
        if let data = try? JSONEncoder().encode(formatDist) {
            userDefaults.set(data, forKey: kFormatDist)
        }
        if let data = try? JSONEncoder().encode(timeSlotDist) {
            userDefaults.set(data, forKey: kTimeSlotDist)
        }
        
        recalculateArtists()
    }
    
    // MARK: - Formatting Helpers
    
    public var formattedTotalTime: String {
        guard totalSongsPlayed > 0 else { return "0 mins" }
        let totalMins = Int(totalSecondsListened) / 60
        if totalMins < 60 {
            return "\(max(0, totalMins)) mins"
        }
        let hours = totalMins / 60
        let mins = totalMins % 60
        return "\(hours)h \(mins)m"
    }
    
    public var hasCircadianData: Bool {
        timeSlotDistribution.values.reduce(0, +) > 0
    }
    
    public var hasJournalData: Bool {
        !listeningJournal.isEmpty
    }

    public var primaryTimeOfDay: String {
        let sorted = timeSlotDistribution.sorted { $0.value > $1.value }
        if let top = sorted.first, top.value > 0 {
            switch top.key {
            case .morning: return "Morning Explorer"
            case .afternoon: return "Afternoon Deep Focus"
            case .evening: return "Evening Lounge"
            case .night: return "Night Owl Session"
            }
        }
        return "Analyzing..."
    }
    
    public var peakListeningWindow: String {
        let sorted = timeSlotDistribution.sorted { $0.value > $1.value }
        if let top = sorted.first, top.value > 0 {
            return top.key.rawValue
        }
        return "Analyzing..."
    }
    
    public var completionPercentage: Double {
        guard !listeningJournal.isEmpty else { return 0.0 }
        let full = listeningJournal.filter { $0.completedFullSong }.count
        return Double(full) / Double(listeningJournal.count)
    }
    
    public var completionCounts: (fullPlays: Int, earlySkips: Int, total: Int) {
        let full = listeningJournal.filter { $0.completedFullSong }.count
        let skips = listeningJournal.filter { $0.wasSkippedEarly }.count
        return (fullPlays: full, earlySkips: skips, total: max(0, listeningJournal.count))
    }
    
    public func timeSlotPercentage(for slot: TimeOfDaySlot) -> Double {
        let total = timeSlotDistribution.values.reduce(0, +)
        guard total > 0 else { return 0.0 }
        let count = timeSlotDistribution[slot, default: 0]
        return Double(count) / Double(total)
    }
    
    // MARK: - Private Logic
    
    private func currentSlot() -> TimeOfDaySlot {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
    
    private func recalculateArtists() {
        var counts: [String: Int] = [:]
        for item in topTracks {
            counts[item.track.artist, default: 0] += item.playCount
        }
        let total = Double(max(1, totalSongsPlayed))
        let sorted = counts.sorted { $0.value > $1.value }
        self.topArtists = sorted.prefix(5).map { (artist: $0.key, count: $0.value, percentage: Double($0.value) / total) }
    }
    
    private func loadPersistedStats() {
        self.totalSongsPlayed = userDefaults.integer(forKey: kTotalSongs)
        let rawSeconds = userDefaults.double(forKey: kTotalSeconds)
        if self.totalSongsPlayed == 0 {
            self.totalSecondsListened = 0.0
            userDefaults.removeObject(forKey: kTotalSeconds)
        } else {
            self.totalSecondsListened = rawSeconds
        }
        self.currentStreakDays = userDefaults.integer(forKey: kStreakDays)
        
        let lastTimestamp = userDefaults.double(forKey: kLastListeningDate)
        if lastTimestamp > 0 {
            self.lastListeningDate = Date(timeIntervalSince1970: lastTimestamp)
        }
        
        if let data = userDefaults.data(forKey: kTopTracks),
           let tracks = try? JSONDecoder().decode([TrackAnalytics].self, from: data) {
            self.topTracks = tracks
            recalculateArtists()
        }
        
        if let data = userDefaults.data(forKey: kJournal),
           let journal = try? JSONDecoder().decode([ListeningEvent].self, from: data) {
            self.listeningJournal = journal
        }
        
        if let dict = userDefaults.dictionary(forKey: kFormatDist) as? [String: Int] {
            self.formatDistribution = dict
        }
        
        if let rawSlots = userDefaults.dictionary(forKey: kTimeSlotDist) as? [String: Int] {
            var slots: [TimeOfDaySlot: Int] = [:]
            for (key, val) in rawSlots {
                if let slot = TimeOfDaySlot(rawValue: key) {
                    slots[slot] = val
                }
            }
            if !slots.isEmpty {
                self.timeSlotDistribution = slots
            }
        }
    }
}
