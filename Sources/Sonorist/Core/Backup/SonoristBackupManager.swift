import Foundation
import Compression

/// Summary details returned after a successful backup restoration
public struct BackupRestoreSummary: Sendable {
    public let playlistCount: Int
    public let favoriteCount: Int
    public let totalSongsPlayed: Int
    public let audioRestoredCount: Int
    public let audioAlreadyPresentCount: Int
    public let offlineSongsNeedDownload: [Track]
    public let hasApiKey: Bool
    
    public init(
        playlistCount: Int,
        favoriteCount: Int,
        totalSongsPlayed: Int,
        audioRestoredCount: Int,
        audioAlreadyPresentCount: Int = 0,
        offlineSongsNeedDownload: [Track] = [],
        hasApiKey: Bool
    ) {
        self.playlistCount = playlistCount
        self.favoriteCount = favoriteCount
        self.totalSongsPlayed = totalSongsPlayed
        self.audioRestoredCount = audioRestoredCount
        self.audioAlreadyPresentCount = audioAlreadyPresentCount
        self.offlineSongsNeedDownload = offlineSongsNeedDownload
        self.hasApiKey = hasApiKey
    }
}

/// Comprehensive, portable Sonorist Settings & Library Package
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
    
    // 6. Optional Embedded Audio Bundles (For backward compatibility)
    public let embeddedAudioBundles: [String: Data]?
}

/// Enterprise-grade, lossless backup and restore engine for Sonorist
public enum SonoristBackupManager {
    public static let magicHeader = "SONORIST_BACKUP".data(using: .utf8)! // 15 bytes
    public static let songsMagicHeader = "SONORIST_SONGS".data(using: .utf8)! // 14 bytes
    public static let currentVersion: UInt16 = 1
    
    // MARK: - Size Estimations
    
    public static func calculateSettingsBackupSize() -> (bytes: Int64, formatted: String) {
        return (65_536, "~64 KB")
    }
    
    public static func calculateSongsBackupSize() -> (bytes: Int64, formatted: String) {
        let cache = MediaCacheManager.shared
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cache.libraryDirectory.path)) ?? []
        let sonoristFiles = files.filter { $0.hasSuffix(".sonorist") }
        var totalBytes: Int64 = 0
        for filename in sonoristFiles {
            let fileURL = cache.libraryDirectory.appendingPathComponent(filename)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let text = formatter.string(fromByteCount: totalBytes)
        return (totalBytes, text)
    }
    
    // MARK: - Export
    
    /// Exports Playlists, Custom Folders, Favorites, Preferences, AI Config, and Telemetry (No Audio Bloat).
    @MainActor
    public static func exportSettingsBackup(
        progressHandler: ((_ progress: Double, _ message: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> URL {
        progressHandler?(0.2, "Gathering playlists & preferences...", 1, 4)
        try? await Task.sleep(nanoseconds: 120_000_000)
        
        let player = AudioPlayerEngine.shared
        let aiConfig = AIProviderConfig.shared
        let themeManager = AppThemeManager.shared
        let analytics = ListeningAnalyticsManager.shared
        let playlistEngine = AIPlaylistEngine.shared
        let cache = MediaCacheManager.shared
        
        let offlineTracks = cache.getAllCachedTracks()
        progressHandler?(0.5, "Encoding configuration & playlists...", 2, 4)
        try? await Task.sleep(nanoseconds: 120_000_000)
        
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
            embeddedAudioBundles: nil
        )
        
        let jsonData = try JSONEncoder().encode(package)
        progressHandler?(0.8, "Packaging backup file...", 3, 4)
        try? await Task.sleep(nanoseconds: 120_000_000)
        
        // Pack with magic header
        var payload = Data()
        payload.append(magicHeader)
        var version = currentVersion.littleEndian
        payload.append(Data(bytes: &version, count: MemoryLayout<UInt16>.size))
        payload.append(jsonData)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = dateFormatter.string(from: Date())
        let filename = "Sonorist_Playlists_Settings_\(dateStr).sonorist-backup"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        try payload.write(to: tempURL, options: .atomic)
        progressHandler?(1.0, "Ready!", 4, 4)
        return tempURL
    }
    
    @MainActor
    public static func exportSettingsBackup(
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> URL {
        try await exportSettingsBackup { p, m, _, _ in
            progressHandler?(p, m)
        }
    }
    
    /// Exports ONLY downloaded offline songs directly in high-efficiency binary container (Zero Base64 overhead).
    @MainActor
    public static func exportSongsBackup(
        progressHandler: ((_ progress: Double, _ message: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> URL {
        let cache = MediaCacheManager.shared
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cache.libraryDirectory.path)) ?? []
        let sonoristFiles = files.filter { $0.hasSuffix(".sonorist") }
        let totalCount = sonoristFiles.count
        let trackMap = Dictionary(cache.getAllCachedTracks().map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        
        progressHandler?(0.05, "Scanning \(totalCount) offline songs...", 0, totalCount)
        
        var payload = Data()
        // 1. Magic Header (14 bytes)
        payload.append(songsMagicHeader)
        
        // 2. Version (UInt16, 2 bytes)
        var version: UInt16 = currentVersion.littleEndian
        payload.append(Data(bytes: &version, count: MemoryLayout<UInt16>.size))
        
        // 3. Track Count (UInt32, 4 bytes)
        var count: UInt32 = UInt32(totalCount).littleEndian
        payload.append(Data(bytes: &count, count: MemoryLayout<UInt32>.size))
        
        // 4. Sequential Song Bundles (Direct raw binary chunks)
        for (index, filename) in sonoristFiles.enumerated() {
            let trackId = String(filename.dropLast(".sonorist".count))
            let fileURL = cache.libraryDirectory.appendingPathComponent(filename)
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            
            let trackTitle = trackMap[trackId] ?? "Song \(index + 1)"
            let progress = Double(index + 1) / Double(max(1, totalCount))
            progressHandler?(0.05 + progress * 0.90, "Packaging: \(trackTitle)", index + 1, totalCount)
            
            // Pacing sleep (20ms) so SwiftUI paints intermediate progress frames visibly
            try? await Task.sleep(nanoseconds: 20_000_000)
            
            // Video ID (Length-prefixed UTF-8)
            let idBytes = Array(trackId.utf8)
            var idLen: UInt16 = UInt16(idBytes.count).littleEndian
            payload.append(Data(bytes: &idLen, count: MemoryLayout<UInt16>.size))
            payload.append(contentsOf: idBytes)
            
            // File Data (Length-prefixed binary)
            var dataLen: UInt64 = UInt64(fileData.count).littleEndian
            payload.append(Data(bytes: &dataLen, count: MemoryLayout<UInt64>.size))
            payload.append(fileData)
        }
        
        progressHandler?(0.98, "Writing backup container...", totalCount, totalCount)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = dateFormatter.string(from: Date())
        let filename = "Sonorist_Songs_\(dateStr).sonorist-songs"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        try payload.write(to: tempURL, options: .atomic)
        progressHandler?(1.0, "All \(totalCount) songs backed up!", totalCount, totalCount)
        return tempURL
    }
    
    @MainActor
    public static func exportSongsBackup(
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> URL {
        try await exportSongsBackup { p, m, _, _ in
            progressHandler?(p, m)
        }
    }
    
    /// Backward-compatible wrapper
    @MainActor
    public static func exportBackup(includeAudio: Bool = false) async throws -> URL {
        if includeAudio {
            return try await exportSongsBackup(progressHandler: nil as ((Double, String) -> Void)?)
        } else {
            return try await exportSettingsBackup(progressHandler: nil as ((Double, String) -> Void)?)
        }
    }
    
    // MARK: - Import & Restore
    
    /// Restores state or songs from a given backup file URL.
    @MainActor
    public static func importBackup(
        from url: URL,
        progressHandler: ((_ progress: Double, _ message: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> BackupRestoreSummary {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        progressHandler?(0.05, "Reading backup file...", 0, 1)
        let data = try Data(contentsOf: url)
        
        // 1. Detect Songs Only format
        if data.starts(with: songsMagicHeader) {
            return try await restoreSongs(from: data, progressHandler: progressHandler)
        }
        
        // 2. Detect Settings format
        if data.starts(with: magicHeader) {
            let offset = magicHeader.count + 2 // header + version
            guard data.count > offset else {
                throw NSError(domain: "SonoristBackupManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid backup file size."])
            }
            progressHandler?(0.25, "Validating settings package...", 1, 3)
            let jsonPayload = data.subdata(in: offset..<data.count)
            let package = try JSONDecoder().decode(SonoristBackupPackage.self, from: jsonPayload)
            return try await applyPackage(package, progressHandler: progressHandler)
        }
        
        // 3. Fallback: Raw JSON package
        if let rawPackage = try? JSONDecoder().decode(SonoristBackupPackage.self, from: data) {
            return try await applyPackage(rawPackage, progressHandler: progressHandler)
        }
        
        throw NSError(domain: "SonoristBackupManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid backup format or unrecognized file header."])
    }
    
    @MainActor
    public static func importBackup(
        from url: URL,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> BackupRestoreSummary {
        try await importBackup(from: url) { p, m, _, _ in
            progressHandler?(p, m)
        }
    }
    
    // MARK: - Private Restore Helpers
    
    @MainActor
    private static func restoreSongs(
        from data: Data,
        progressHandler: ((_ progress: Double, _ message: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> BackupRestoreSummary {
        let offset = songsMagicHeader.count + 2 // header + version
        guard data.count >= offset + 4 else {
            throw NSError(domain: "SonoristBackupManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Corrupted songs backup file."])
        }
        
        var currentOffset = offset
        let count: UInt32 = data.subdata(in: currentOffset..<(currentOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        currentOffset += 4
        
        let cache = MediaCacheManager.shared
        let existingTracks = cache.getAllCachedTracks()
        let existingMap = Dictionary(existingTracks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        
        var restoredCount = 0
        var alreadyPresentCount = 0
        let totalCount = Int(count)
        
        for index in 0..<totalCount {
            guard currentOffset + 2 <= data.count else { break }
            let idLen: UInt16 = data.subdata(in: currentOffset..<(currentOffset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
            currentOffset += 2
            
            guard currentOffset + Int(idLen) <= data.count else { break }
            let idData = data.subdata(in: currentOffset..<(currentOffset + Int(idLen)))
            guard let trackId = String(data: idData, encoding: .utf8) else { break }
            currentOffset += Int(idLen)
            
            guard currentOffset + 8 <= data.count else { break }
            let dataLen: UInt64 = data.subdata(in: currentOffset..<(currentOffset + 8)).withUnsafeBytes { $0.load(as: UInt64.self) }.littleEndian
            currentOffset += 8
            
            guard currentOffset + Int(dataLen) <= data.count else { break }
            let bundleData = data.subdata(in: currentOffset..<(currentOffset + Int(dataLen)))
            currentOffset += Int(dataLen)
            
            let targetURL = cache.libraryDirectory.appendingPathComponent("\(trackId).sonorist")
            let isAlreadyCached = cache.isCached(videoId: trackId) || FileManager.default.fileExists(atPath: targetURL.path)
            
            let trackTitle: String
            if let meta = try? SonoristBundleEngine.readMetadataOnly(from: bundleData) {
                trackTitle = meta.track.title
            } else if let title = existingMap[trackId] {
                trackTitle = title
            } else {
                trackTitle = "Song \(index + 1)"
            }
            
            let progress = Double(index + 1) / Double(max(1, totalCount))
            
            if isAlreadyCached {
                // Song already exists in offline library - DO NOT overwrite
                alreadyPresentCount += 1
                progressHandler?(0.05 + progress * 0.90, "Already present: \(trackTitle)", index + 1, totalCount)
            } else {
                // Restore new song
                try? bundleData.write(to: targetURL, options: .atomic)
                restoredCount += 1
                progressHandler?(0.05 + progress * 0.90, "Restoring: \(trackTitle)", index + 1, totalCount)
            }
            
            // Extract embedded album art directly to ArtworkCache for instant display
            if let meta = try? SonoristBundleEngine.readMetadataOnly(from: bundleData),
               let artData = meta.artworkData, !artData.isEmpty {
                let artFileURL = cache.artworkDirectory.appendingPathComponent("\(trackId).jpg")
                if !FileManager.default.fileExists(atPath: artFileURL.path) {
                    try? artData.write(to: artFileURL, options: .atomic)
                }
            }
            
            // Pacing sleep (20ms) so the restore loading bar visibly moves
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        progressHandler?(0.98, "Updating offline library manifest...", totalCount, totalCount)
        if restoredCount > 0 {
            cache.reloadManifest()
        }
        
        let completionMsg: String
        if alreadyPresentCount > 0 && restoredCount > 0 {
            completionMsg = "Out of \(totalCount) songs, \(restoredCount) restored and \(alreadyPresentCount) already present."
        } else if restoredCount == 0 && alreadyPresentCount > 0 {
            completionMsg = "All \(alreadyPresentCount) songs already present in your library."
        } else {
            completionMsg = "Restored all \(restoredCount) songs!"
        }
        progressHandler?(1.0, completionMsg, totalCount, totalCount)
        
        return BackupRestoreSummary(
            playlistCount: 0,
            favoriteCount: 0,
            totalSongsPlayed: 0,
            audioRestoredCount: restoredCount,
            audioAlreadyPresentCount: alreadyPresentCount,
            offlineSongsNeedDownload: [],
            hasApiKey: false
        )
    }
    
    @MainActor
    private static func applyPackage(
        _ package: SonoristBackupPackage,
        progressHandler: ((_ progress: Double, _ message: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> BackupRestoreSummary {
        let player = AudioPlayerEngine.shared
        let aiConfig = AIProviderConfig.shared
        let themeManager = AppThemeManager.shared
        let analytics = ListeningAnalyticsManager.shared
        let playlistEngine = AIPlaylistEngine.shared
        let cache = MediaCacheManager.shared
        
        progressHandler?(0.35, "Restoring theme & playback preferences...", 1, 3)
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
        
        progressHandler?(0.65, "Restoring playlists & favorites...", 2, 3)
        // 4. Restore Playlists & Liked Tracks
        playlistEngine.curatedLibrary = package.curatedLibrary
        playlistEngine.saveLibrary()
        
        player.likedTracks = package.likedTracks
        player.saveLikedTracks()
        
        // 5. Restore Analytics
        // Safeguard: Only restore telemetry if package contains real data,
        // and if it was a legacy audio-bundled package, do not wipe out active device analytics.
        let isLegacyAudioPackage = package.embeddedAudioBundles != nil && !package.embeddedAudioBundles!.isEmpty
        let hasTelemetry = package.totalSongsPlayed > 0 || !package.listeningJournal.isEmpty
        let shouldRestoreAnalytics = hasTelemetry && (!isLegacyAudioPackage || analytics.totalSongsPlayed == 0)
        
        if shouldRestoreAnalytics {
            analytics.restoreFromBackup(
                totalSeconds: package.totalSecondsListened,
                totalSongs: package.totalSongsPlayed,
                streakDays: package.streakDays,
                topTracks: package.topTracks,
                journal: package.listeningJournal,
                formatDist: package.formatDistribution,
                timeSlotDist: package.timeSlotDistribution
            )
        }
        
        // 6. Restore Offline Audio or Manifest
        var audioRestored = 0
        var audioAlreadyPresent = 0
        var needsDownload: [Track] = []
        
        if let bundles = package.embeddedAudioBundles, !bundles.isEmpty {
            let totalBundles = bundles.count
            for (index, (trackId, bundleData)) in bundles.enumerated() {
                let targetURL = cache.libraryDirectory.appendingPathComponent("\(trackId).sonorist")
                let isAlreadyCached = cache.isCached(videoId: trackId) || FileManager.default.fileExists(atPath: targetURL.path)
                let progress = Double(index + 1) / Double(totalBundles)
                
                if isAlreadyCached {
                    audioAlreadyPresent += 1
                    progressHandler?(0.7 + progress * 0.28, "Already present: Song \(index + 1)", index + 1, totalBundles)
                } else {
                    try? bundleData.write(to: targetURL, options: .atomic)
                    audioRestored += 1
                    progressHandler?(0.7 + progress * 0.28, "Restoring legacy audio \(index + 1) of \(totalBundles)...", index + 1, totalBundles)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if audioRestored > 0 {
                cache.reloadManifest()
            }
        } else {
            for track in package.offlineManifest {
                if !cache.isCached(videoId: track.id) {
                    needsDownload.append(track)
                } else {
                    audioAlreadyPresent += 1
                }
            }
        }
        
        progressHandler?(1.0, "Restore completed!", 3, 3)
        return BackupRestoreSummary(
            playlistCount: package.curatedLibrary.totalTrackCount,
            favoriteCount: package.likedTracks.count,
            totalSongsPlayed: package.totalSongsPlayed,
            audioRestoredCount: audioRestored,
            audioAlreadyPresentCount: audioAlreadyPresent,
            offlineSongsNeedDownload: needsDownload,
            hasApiKey: !package.aiApiKey.isEmpty
        )
    }
}
