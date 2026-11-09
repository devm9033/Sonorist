import Foundation
import Compression

/// Summary details returned after a successful backup restoration
public struct BackupRestoreSummary: Sendable {
    public let playlistCount: Int
    public let favoriteCount: Int
    public let totalSongsPlayed: Int
    public let audioRestoredCount: Int
    public let offlineSongsNeedDownload: [Track]
    public let hasApiKey: Bool
    
    public init(
        playlistCount: Int,
        favoriteCount: Int,
        totalSongsPlayed: Int,
        audioRestoredCount: Int,
        offlineSongsNeedDownload: [Track] = [],
        hasApiKey: Bool
    ) {
        self.playlistCount = playlistCount
        self.favoriteCount = favoriteCount
        self.totalSongsPlayed = totalSongsPlayed
        self.audioRestoredCount = audioRestoredCount
        self.offlineSongsNeedDownload = offlineSongsNeedDownload
        self.hasApiKey = hasApiKey
    }
}

/// Comprehensive, portable Sonorist Backup Package
public struct SonoristBackupPackage: Codable, Sendable {
    public let version: Int
    public let timestamp: Date
    public let appVersion: String
    
    // 1. Settings & Audio Preferences
    public let theme: String
    public let audioQuality: String
    public let isCrossfadeEnabled: Bool
    public let crossfadeDuration: Double
    public let isAutoplayEnabled: Bool
    public let isAudioNormalized: Bool
    public let isEqualizerEnabled: Bool
    public let equalizerPreset: String
    
    // 2. AI Configuration
    public let aiApiKey: String
    public let aiSelectedModelId: String
    public let aiAutoCurateOnDownload: Bool
    
    // 3. Playlists & Library
    public let curatedLibrary: AICuratedLibrary
    public let likedTracks: [Track]
    
    // 4. Analytics & Listening Telemetry
    public let totalSecondsListened: Double
    public let totalSongsPlayed: Int
    public let streakDays: Int
    public let topTracks: [TrackAnalytics]
    public let listeningJournal: [ListeningEvent]
    public let formatDistribution: [String: Int]
    public let timeSlotDistribution: [TimeOfDaySlot: Int]
    
    // 5. Offline Song Manifest
    public let offlineManifest: [Track]
    
    // 6. Optional Embedded Audio Bundles (For Full Offline Vault Archives)
    // Key: trackId, Value: raw .sonorist binary payload
    public let embeddedAudioBundles: [String: Data]?
}

/// Enterprise-grade, lossless backup and restore engine for Sonorist
public enum SonoristBackupManager {
    public static let magicHeader = "SONORIST_BACKUP".data(using: .utf8)! // 15 bytes
    public static let currentVersion: UInt16 = 1
    
    // MARK: - Export
    
    /// Exports all settings, API keys, playlists, favorites, insights, and offline manifests.
    /// If `includeAudio` is true, embeds all actual offline audio files into a single vault file.
    @MainActor
    public static func exportBackup(includeAudio: Bool = false) async throws -> URL {
        let player = AudioPlayerEngine.shared
        let aiConfig = AIProviderConfig.shared
        let themeManager = AppThemeManager.shared
        let analytics = ListeningAnalyticsManager.shared
        let playlistEngine = AIPlaylistEngine.shared
        let cache = MediaCacheManager.shared
        
        let offlineTracks = cache.getAllCachedTracks()
        
        var embeddedBundles: [String: Data]? = nil
        if includeAudio {
            var bundles: [String: Data] = [:]
            for track in offlineTracks {
                let fileURL = cache.libraryDirectory.appendingPathComponent("\(track.id).sonorist")
                if let data = try? Data(contentsOf: fileURL) {
                    bundles[track.id] = data
                }
            }
            embeddedBundles = bundles
        }
        
        let package = SonoristBackupPackage(
            version: 1,
            timestamp: Date(),
            appVersion: "1.0.0",
            theme: themeManager.currentTheme.rawValue,
            audioQuality: player.selectedAudioQuality.rawValue,
            isCrossfadeEnabled: player.isCrossfadeEnabled,
            crossfadeDuration: player.crossfadeDuration,
            isAutoplayEnabled: player.isAutoplayEnabled,
            isAudioNormalized: player.isAudioNormalized,
            isEqualizerEnabled: player.isEqualizerEnabled,
            equalizerPreset: player.equalizerPreset,
            aiApiKey: aiConfig.apiKey,
            aiSelectedModelId: aiConfig.selectedModelId,
            aiAutoCurateOnDownload: aiConfig.isAutoCurateOnDownloadEnabled,
            curatedLibrary: playlistEngine.curatedLibrary,
            likedTracks: player.likedTracks,
            totalSecondsListened: analytics.totalSecondsListened,
            totalSongsPlayed: analytics.totalSongsPlayed,
            streakDays: analytics.currentStreakDays,
            topTracks: analytics.topTracks,
            listeningJournal: analytics.listeningJournal,
            formatDistribution: analytics.formatDistribution,
            timeSlotDistribution: analytics.timeSlotDistribution,
            offlineManifest: offlineTracks,
            embeddedAudioBundles: embeddedBundles
        )
        
        let jsonData = try JSONEncoder().encode(package)
        
        // Pack with magic header
        var payload = Data()
        payload.append(magicHeader)
        var version = currentVersion.littleEndian
        payload.append(Data(bytes: &version, count: MemoryLayout<UInt16>.size))
        payload.append(jsonData)
        
        // Write to a temporary file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = dateFormatter.string(from: Date())
        
        let ext = includeAudio ? "sonorist-vault" : "sonorist-backup"
        let filename = "Sonorist_Backup_\(dateStr).\(ext)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        try payload.write(to: tempURL, options: .atomic)
        return tempURL
    }
    
    // MARK: - Import & Restore
    
    /// Restores full state from a given backup file URL.
    @MainActor
    public static func importBackup(from url: URL) async throws -> BackupRestoreSummary {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let data = try Data(contentsOf: url)
        
        // Validate magic header
        guard data.count > magicHeader.count + 2 else {
            throw NSError(domain: "SonoristBackupManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid backup file size."])
        }
        
        let header = data.prefix(magicHeader.count)
        guard header == magicHeader else {
            // Also accept raw JSON package for developer convenience
            if let rawPackage = try? JSONDecoder().decode(SonoristBackupPackage.self, from: data) {
                return try applyPackage(rawPackage)
            }
            throw NSError(domain: "SonoristBackupManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid backup format or corrupted file header."])
        }
        
        let offset = magicHeader.count + 2 // header + version
        let jsonPayload = data.subdata(in: offset..<data.count)
        
        let package = try JSONDecoder().decode(SonoristBackupPackage.self, from: jsonPayload)
        return try applyPackage(package)
    }
    
    // MARK: - Restore Application
    
    @MainActor
    private static func applyPackage(_ package: SonoristBackupPackage) throws -> BackupRestoreSummary {
        let player = AudioPlayerEngine.shared
        let aiConfig = AIProviderConfig.shared
        let themeManager = AppThemeManager.shared
        let analytics = ListeningAnalyticsManager.shared
        let playlistEngine = AIPlaylistEngine.shared
        let cache = MediaCacheManager.shared
        
        // 1. Restore Theme
        if let mode = AppThemeMode(rawValue: package.theme) {
            themeManager.setTheme(mode)
        }
        
        // 2. Restore Audio Quality & Playback
        if let quality = AudioQuality(rawValue: package.audioQuality) {
            player.switchQuality(to: quality)
        }
        player.isCrossfadeEnabled = package.isCrossfadeEnabled
        player.crossfadeDuration = package.crossfadeDuration
        player.isAutoplayEnabled = package.isAutoplayEnabled
        player.isAudioNormalized = package.isAudioNormalized
        player.isEqualizerEnabled = package.isEqualizerEnabled
        player.setEqualizerPreset(package.equalizerPreset)
        
        // 3. Restore AI Config
        aiConfig.apiKey = package.aiApiKey
        aiConfig.selectedModelId = package.aiSelectedModelId
        aiConfig.isAutoCurateOnDownloadEnabled = package.aiAutoCurateOnDownload
        
        // 4. Restore Playlists & Liked Tracks
        playlistEngine.curatedLibrary = package.curatedLibrary
        playlistEngine.saveLibrary()
        
        player.likedTracks = package.likedTracks
        player.saveLikedTracks()
        
        // 5. Restore Analytics
        analytics.restoreFromBackup(
            totalSeconds: package.totalSecondsListened,
            totalSongs: package.totalSongsPlayed,
            streakDays: package.streakDays,
            topTracks: package.topTracks,
            journal: package.listeningJournal,
            formatDist: package.formatDistribution,
            timeSlotDist: package.timeSlotDistribution
        )
        
        // 6. Restore Offline Audio or Manifest
        var audioRestored = 0
        var needsDownload: [Track] = []
        
        if let bundles = package.embeddedAudioBundles, !bundles.isEmpty {
            for (trackId, bundleData) in bundles {
                let targetURL = cache.libraryDirectory.appendingPathComponent("\(trackId).sonorist")
                try? bundleData.write(to: targetURL, options: .atomic)
                audioRestored += 1
            }
            cache.reloadManifest()
        } else {
            // Check which tracks are already in cache vs which need re-downloading
            for track in package.offlineManifest {
                if !cache.isCached(videoId: track.id) {
                    needsDownload.append(track)
                }
            }
        }
        
        return BackupRestoreSummary(
            playlistCount: package.curatedLibrary.totalTrackCount,
            favoriteCount: package.likedTracks.count,
            totalSongsPlayed: package.totalSongsPlayed,
            audioRestoredCount: audioRestored,
            offlineSongsNeedDownload: needsDownload,
            hasApiKey: !package.aiApiKey.isEmpty
        )
    }
}
