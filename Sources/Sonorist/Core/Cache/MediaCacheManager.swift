import Foundation
import Combine
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif
import AVFoundation
import CoreMedia

/// Local media cache and library manager for offline playback
/// Implements the unified 3-folder parent structure: Library, Exports, and History.
/// Follows ECC security guidelines for local storage containment and Apple Design specifications.
public final class MediaCacheManager: @unchecked Sendable {
    public static let shared = MediaCacheManager()
    
    private let fileManager = FileManager.default
    public let parentDirectory: URL
    public let libraryDirectory: URL
    public let exportsDirectory: URL
    public let historyDirectory: URL
    public let playbackTempDirectory: URL
    public let artworkDirectory: URL
    
    private let manifestURL: URL
    private let queue = DispatchQueue(label: "com.sonorist.mac.cache", qos: .utility)
    
    private var cachedManifest: [String: String] = [:] // videoId -> local .sonorist filename
    private var cachedTracksMetadata: [String: Track] = [:] // videoId -> Track
    private var cachedIdsSet: Set<String> = []
    
    public init() {
        // Preferred: Sandboxed Application Support directory
        let defaultAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appFolder = defaultAppSupport?.appendingPathComponent("Sonorist", isDirectory: true)
        
        // Defensive fallback: If Application Support is restricted in sandbox, use /tmp/Sonorist
        let baseDir: URL
        if let folder = appFolder,
           (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil &&
           fileManager.isWritableFile(atPath: folder.path) {
            baseDir = folder
        } else {
            baseDir = URL(fileURLWithPath: "/tmp/Sonorist", isDirectory: true)
            try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        
        self.parentDirectory = baseDir
        self.libraryDirectory = baseDir.appendingPathComponent("Library", isDirectory: true)
        self.exportsDirectory = baseDir.appendingPathComponent("Exports", isDirectory: true)
        self.historyDirectory = baseDir.appendingPathComponent("History", isDirectory: true)
        self.artworkDirectory = baseDir.appendingPathComponent("ArtworkCache", isDirectory: true)
        self.playbackTempDirectory = baseDir.appendingPathComponent("PlaybackTemp", isDirectory: true)
        self.manifestURL = libraryDirectory.appendingPathComponent("library_manifest.json")
        
        setupDirectories()
        migrateLegacyCacheIfNeeded()
        loadManifest()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.getAllCachedTracks()
        }
    }
    
    private var didSetupDirectories = false
    public func setupDirectories(force: Bool = false) {
        if !force && didSetupDirectories { return }
        didSetupDirectories = true
        let dirs = [parentDirectory, libraryDirectory, exportsDirectory, historyDirectory, artworkDirectory, playbackTempDirectory]
        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        
        // Exclude media library cache from iCloud backup per Apple App Store Guideline 5.1.1
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableParent = parentDirectory
        try? mutableParent.setResourceValues(resourceValues)
    }
    
    private func migrateLegacyCacheIfNeeded() {
        // Automatically migrate any legacy MetrolistMac cache files
        guard let defaultAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacyFolder = defaultAppSupport.appendingPathComponent("MetrolistMac")
        let legacyAudioCache = legacyFolder.appendingPathComponent("AudioCache")
        
        if fileManager.fileExists(atPath: legacyAudioCache.path) {
            if let files = try? fileManager.contentsOfDirectory(atPath: legacyAudioCache.path) {
                for file in files {
                    let oldURL = legacyAudioCache.appendingPathComponent(file)
                    let newURL = libraryDirectory.appendingPathComponent(file)
                    if !fileManager.fileExists(atPath: newURL.path) {
                        try? fileManager.moveItem(at: oldURL, to: newURL)
                    }
                }
            }
            try? fileManager.removeItem(at: legacyAudioCache)
        }
    }
    
    private func loadManifest() {
        if let data = try? Data(contentsOf: manifestURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.cachedManifest = dict
            self.cachedIdsSet = Set(dict.keys)
        }
        
        // Scan library directory for any newly dropped .sonorist files
        if let files = try? fileManager.contentsOfDirectory(atPath: libraryDirectory.path) {
            for file in files where file.hasSuffix(".sonorist") {
                let vid = String(file.dropLast(".sonorist".count))
                if !self.cachedIdsSet.contains(vid) {
                    self.cachedManifest[vid] = file
                    self.cachedIdsSet.insert(vid)
                }
            }
        }
    }
    
    private func saveManifest() {
        if let data = try? JSONEncoder().encode(cachedManifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
    
    // MARK: - Query & Lookup
    
    /// Checks if a track is available offline (instant zero-IO lookup with disk fallback)
    public func isCached(videoId: String) -> Bool {
        return queue.sync {
            let safeId = videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            let lookupId = safeId.isEmpty ? videoId : safeId
            let filename = cachedManifest[lookupId] ?? cachedManifest[videoId] ?? "\(lookupId).sonorist"
            let candidate = libraryDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: candidate.path) {
                cachedManifest[lookupId] = filename
                cachedIdsSet.insert(lookupId)
                cachedIdsSet.insert(videoId)
                return true
            }
            cachedIdsSet.remove(lookupId)
            cachedIdsSet.remove(videoId)
            return false
        }
    }
    
    /// Returns the local bundle file URL if cached
    public func cachedURL(for videoId: String) -> URL? {
        return queue.sync {
            let filename = cachedManifest[videoId] ?? "\(videoId).sonorist"
            let fileURL = libraryDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path) {
                if cachedManifest[videoId] == nil {
                    cachedManifest[videoId] = filename
                    cachedIdsSet.insert(videoId)
                }
                return fileURL
            }
            return nil
        }
    }
    
    /// Returns a local file:// URL pointing to the high-res extracted artwork on disk
    public func cachedArtworkURL(for videoId: String) -> URL? {
        return queue.sync {
            internalCachedArtworkURL(for: videoId)
        }
    }
    
    /// Un-synchronized internal helper to prevent GCD recursive dispatch deadlock
    private func internalCachedArtworkURL(for videoId: String) -> URL? {
        let artFileURL = self.artworkDirectory.appendingPathComponent("\(videoId).jpg")
        if fileManager.fileExists(atPath: artFileURL.path) {
            return artFileURL
        }
        
        // If not yet extracted on disk, extract once from the .sonorist binary container
        let filename = cachedManifest[videoId] ?? "\(videoId).sonorist"
        let bundleURL = libraryDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: bundleURL.path),
              let data = try? Data(contentsOf: bundleURL),
              let meta = try? SonoristBundleEngine.readMetadataOnly(from: data),
              let artData = meta.artworkData, !artData.isEmpty else {
            return nil
        }
        
        try? artData.write(to: artFileURL, options: .atomic)
        return fileManager.fileExists(atPath: artFileURL.path) ? artFileURL : nil
    }
    
    /// Prepares real-time in-memory playback for a .sonorist bundle
    public func preparePlaybackStream(for videoId: String) -> URL? {
        return queue.sync {
            let safeId = videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            let lookupId = safeId.isEmpty ? videoId : safeId
            let filename = cachedManifest[lookupId] ?? cachedManifest[videoId] ?? "\(lookupId).sonorist"
            let bundleURL = libraryDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: bundleURL.path) else { return nil }
            
            if cachedManifest[lookupId] == nil {
                cachedManifest[lookupId] = filename
                cachedIdsSet.insert(lookupId)
                cachedIdsSet.insert(videoId)
            }
            
            // Ensure temp directory exists
            try? fileManager.createDirectory(at: playbackTempDirectory, withIntermediateDirectories: true)
            
            // Check if already extracted in temp directory
            let tempPlayURL = playbackTempDirectory.appendingPathComponent("\(lookupId).m4a")
            if fileManager.fileExists(atPath: tempPlayURL.path),
               let attr = try? fileManager.attributesOfItem(atPath: tempPlayURL.path),
               let size = attr[.size] as? Int64, size > 1024 {
                return tempPlayURL
            }
            
            guard let bundleData = try? Data(contentsOf: bundleURL) else { return nil }
            
            // If it's a proprietary .sonorist container, decompress in real-time
            if filename.hasSuffix(".sonorist") {
                guard let bundle = try? SonoristBundleEngine.unpack(data: bundleData) else {
                    #if DEBUG
                    print("[preparePlaybackStream]: Failed to unpack .sonorist bundle for \(videoId)")
                    #endif
                    return nil
                }
                guard !bundle.audioData.isEmpty else {
                    #if DEBUG
                    print("[preparePlaybackStream]: Decompressed audio is empty for \(videoId)")
                    #endif
                    return nil
                }
                
                do {
                    try bundle.audioData.write(to: tempPlayURL, options: .atomic)
                    guard fileManager.fileExists(atPath: tempPlayURL.path) else { return nil }
                    return tempPlayURL
                } catch {
                    #if DEBUG
                    print("[preparePlaybackStream]: Failed to write audio to \(tempPlayURL.path): \(error)")
                    #endif
                    return nil
                }
            } else {
                // Legacy uncompressed stream file
                return bundleURL
            }
        }
    }
    
    /// Retrieves cached lyrics from the .sonorist bundle in O(1) time
    public func getCachedLyrics(for videoId: String) -> [LyricLine]? {
        return queue.sync {
            let filename = cachedManifest[videoId] ?? "\(videoId).sonorist"
            let bundleURL = libraryDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: bundleURL.path),
                  let data = try? Data(contentsOf: bundleURL),
                  let meta = try? SonoristBundleEngine.readMetadataOnly(from: data),
                  !meta.lyrics.isEmpty else { return nil }
            return meta.lyrics
        }
    }
    
    /// Returns all saved offline tracks from the compressed library (instant O(1) in-memory fast-path)
    public func getAllCachedTracks() -> [Track] {
        return queue.sync {
            var valid: [Track] = []
            for (vid, filename) in cachedManifest {
                let fileURL = libraryDirectory.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                
                // 1. Instant in-memory fast-path: zero disk I/O
                if let track = cachedTracksMetadata[vid] {
                    var t = track
                    t.isCached = true
                    t.streamURL = nil
                    let artFileURL = self.artworkDirectory.appendingPathComponent("\(vid).jpg")
                    if fileManager.fileExists(atPath: artFileURL.path) {
                        t.artworkURL = artFileURL
                    }
                    valid.append(t)
                    continue
                }
                
                // 2. Slow-path (first run cold read only): parse metadata once and cache in RAM
                if filename.hasSuffix(".sonorist") {
                    if let data = try? Data(contentsOf: fileURL),
                       let meta = try? SonoristBundleEngine.readMetadataOnly(from: data) {
                        var t = meta.track
                        t.isCached = true
                        t.streamURL = nil // Never set streamURL to the raw .sonorist bundle file
                        
                        // Extract and link local file artwork for flawless offline display
                        let artFileURL = self.artworkDirectory.appendingPathComponent("\(vid).jpg")
                        if fileManager.fileExists(atPath: artFileURL.path) {
                            t.artworkURL = artFileURL
                        } else if let artData = meta.artworkData, !artData.isEmpty {
                            try? artData.write(to: artFileURL, options: .atomic)
                            if fileManager.fileExists(atPath: artFileURL.path) {
                                t.artworkURL = artFileURL
                            }
                        }
                        
                        valid.append(t)
                        self.cachedTracksMetadata[vid] = t
                        continue
                    }
                }
            }
            return valid.sorted { t1, t2 in
                t1.title.localizedCaseInsensitiveCompare(t2.title) == .orderedAscending
            }
        }
    }
    
    // MARK: - Saving & Packaging (.sonorist)
    
    /// Packs and saves a track, lyrics, artwork, and compressed audio into the Sonorist library
    public func saveBundle(
        track: Track,
        audioData: Data,
        lyrics: [LyricLine] = [],
        artworkData: Data? = nil
    ) {
        queue.sync {
            setupDirectories()
            pruneCacheIfNeeded(incomingBytes: Int64(audioData.count))
            do {
                let bundleData = try SonoristBundleEngine.pack(
                    track: track,
                    audioData: audioData,
                    lyrics: lyrics,
                    artworkData: artworkData
                )
                
                let safeId = track.id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                guard !safeId.isEmpty else { return }
                let filename = "\(safeId).sonorist"
                let destURL = self.libraryDirectory.appendingPathComponent(filename)
                try bundleData.write(to: destURL, options: .atomic)
                
                // Cache artwork to local file for instant offline image loading
                if let art = artworkData, !art.isEmpty {
                    let artFileURL = self.artworkDirectory.appendingPathComponent("\(safeId).jpg")
                    try? art.write(to: artFileURL, options: .atomic)
                }
                
                self.cachedManifest[safeId] = filename
                self.cachedIdsSet.insert(safeId)
                var t = track
                t.isCached = true
                if let localArt = internalCachedArtworkURL(for: safeId) {
                    t.artworkURL = localArt
                }
                self.cachedTracksMetadata[safeId] = t
                self.saveManifest()

                // Silently trigger background AI playlist classification
                Task.detached(priority: .background) {
                    await AIPlaylistEngine.shared.categorizeNewTrack(t)
                }
            } catch {
                #if DEBUG
                print("[Sonorist Bundle Save Error]: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Backward compatible cacheTrack method: automatically wraps into .sonorist
    public func cacheTrack(track: Track, data: Data) {
        saveBundle(track: track, audioData: data, lyrics: [], artworkData: nil)
    }
    
    // MARK: - Exporting Outside the App
    
    /// Writes audio data with embedded Apple M4A metadata tags (Title, Artist, Album, Artwork, Lyrics)
    private func writeTaggedAudioFile(
        audioData: Data,
        track: Track,
        lyrics: [LyricLine],
        artworkData: Data?,
        destinationURL: URL
    ) {
        // 1. Write raw audio stream to a temporary staging file
        let tempInputURL = playbackTempDirectory.appendingPathComponent("staging_\(UUID().uuidString).m4a")
        do {
            try fileManager.createDirectory(at: playbackTempDirectory, withIntermediateDirectories: true)
            try audioData.write(to: tempInputURL, options: .atomic)
            
            // 2. Build metadata items
            var metadataItems: [AVMetadataItem] = []
            
            let titleItem = AVMutableMetadataItem()
            titleItem.keySpace = .common
            titleItem.key = AVMetadataKey.commonKeyTitle as NSString
            titleItem.value = track.title as NSString
            metadataItems.append(titleItem)
            
            let artistItem = AVMutableMetadataItem()
            artistItem.keySpace = .common
            artistItem.key = AVMetadataKey.commonKeyArtist as NSString
            artistItem.value = track.artist as NSString
            metadataItems.append(artistItem)
            
            if let album = track.album, !album.isEmpty {
                let albumItem = AVMutableMetadataItem()
                albumItem.keySpace = .common
                albumItem.key = AVMetadataKey.commonKeyAlbumName as NSString
                albumItem.value = album as NSString
                metadataItems.append(albumItem)
            }
            
            if let artData = artworkData, !artData.isEmpty {
                let artItem = AVMutableMetadataItem()
                artItem.keySpace = .common
                artItem.key = AVMetadataKey.commonKeyArtwork as NSString
                artItem.value = artData as NSData
                artItem.dataType = kCMMetadataBaseDataType_JPEG as String
                metadataItems.append(artItem)
            }
            
            if !lyrics.isEmpty {
                let fullLyricsText = lyrics.map { line in
                    let mins = Int(line.time) / 60
                    let secs = Int(line.time) % 60
                    let ms = Int((line.time.truncatingRemainder(dividingBy: 1.0)) * 100)
                    return String(format: "[%02d:%02d.%02d]%@", mins, secs, ms, line.text)
                }.joined(separator: "\n")
                
                let lyricsItem = AVMutableMetadataItem()
                lyricsItem.keySpace = .iTunes
                lyricsItem.key = "©lyr" as NSString
                lyricsItem.value = fullLyricsText as NSString
                metadataItems.append(lyricsItem)
            }
            
            // 3. Export using AVAssetExportSession
            let asset = AVURLAsset(url: tempInputURL)
            if let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                exportSession.outputURL = destinationURL
                exportSession.outputFileType = .m4a
                exportSession.metadata = metadataItems
                try? fileManager.removeItem(at: destinationURL)
                
                let sema = DispatchSemaphore(value: 0)
                exportSession.exportAsynchronously {
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 4.0)
                
                try? fileManager.removeItem(at: tempInputURL)
                
                if exportSession.status == .completed && fileManager.fileExists(atPath: destinationURL.path) {
                    return
                }
            }
            
            // Fallback: If AVAssetExportSession failed or preset not applicable, write direct audio data
            try? fileManager.removeItem(at: tempInputURL)
            try audioData.write(to: destinationURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: tempInputURL)
            try? audioData.write(to: destinationURL, options: .atomic)
        }
    }
    
    /// Exports an offline track to a standard .m4a audio file outside the app with embedded metadata, lyrics, and artwork
    public func exportTrack(videoId: String, destinationURL: URL) throws {
        try queue.sync {
            guard let filename = cachedManifest[videoId] else {
                throw NSError(domain: "MediaCacheManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track not found in offline library."])
            }
            
            let fileURL = libraryDirectory.appendingPathComponent(filename)
            guard let bundleData = try? Data(contentsOf: fileURL) else {
                throw NSError(domain: "MediaCacheManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to read bundle data."])
            }
            
            if filename.hasSuffix(".sonorist") {
                let bundle = try SonoristBundleEngine.unpack(data: bundleData)
                writeTaggedAudioFile(
                    audioData: bundle.audioData,
                    track: bundle.track,
                    lyrics: bundle.lyrics,
                    artworkData: bundle.artworkData,
                    destinationURL: destinationURL
                )
            } else {
                let meta = cachedTracksMetadata[videoId] ?? Track(id: videoId, title: "Exported Track", artist: "Unknown Artist", audioFormat: "AAC")
                writeTaggedAudioFile(
                    audioData: bundleData,
                    track: meta,
                    lyrics: [],
                    artworkData: nil,
                    destinationURL: destinationURL
                )
            }
        }
    }
    
    /// Exports all offline tracks to a specified folder outside the app with embedded metadata, lyrics, and artwork
    public func exportAllTracks(to folderURL: URL) throws -> Int {
        return try queue.sync {
            guard fileManager.fileExists(atPath: folderURL.path) else {
                throw NSError(domain: "MediaCacheManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Destination folder does not exist."])
            }
            var count = 0
            for (vid, filename) in cachedManifest {
                let fileURL = libraryDirectory.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: fileURL.path),
                      let bundleData = try? Data(contentsOf: fileURL) else { continue }
                
                let trackName: String
                let audioData: Data
                let track: Track
                let lyrics: [LyricLine]
                let artworkData: Data?
                
                if filename.hasSuffix(".sonorist"),
                   let bundle = try? SonoristBundleEngine.unpack(data: bundleData) {
                    audioData = bundle.audioData
                    track = bundle.track
                    lyrics = bundle.lyrics
                    artworkData = bundle.artworkData
                    trackName = "\(bundle.track.artist) - \(bundle.track.title)"
                } else {
                    audioData = bundleData
                    let meta = cachedTracksMetadata[vid]
                    track = meta ?? Track(id: vid, title: vid, artist: "Unknown", audioFormat: "AAC")
                    lyrics = []
                    artworkData = nil
                    if let meta = meta {
                        trackName = "\(meta.artist) - \(meta.title)"
                    } else {
                        trackName = vid
                    }
                }
                
                // Sanitize file name for filesystem
                let safeName = trackName
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: " -")
                    .replacingOccurrences(of: "\\", with: "-")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let dest = folderURL.appendingPathComponent("\(safeName).m4a")
                writeTaggedAudioFile(
                    audioData: audioData,
                    track: track,
                    lyrics: lyrics,
                    artworkData: artworkData,
                    destinationURL: dest
                )
                count += 1
            }
            return count
        }
    }
    
    // MARK: - Deletion & Purging
    
    /// Removes a single track from the offline library
    public func removeCachedTrack(videoId: String) {
        let safeId = videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeId.isEmpty else { return }
        queue.sync {
            if let filename = self.cachedManifest[safeId] {
                let fileURL = self.libraryDirectory.appendingPathComponent(filename)
                try? self.fileManager.removeItem(at: fileURL)
                self.cachedManifest.removeValue(forKey: safeId)
                self.cachedIdsSet.remove(safeId)
                self.cachedTracksMetadata.removeValue(forKey: safeId)
                self.saveManifest()
            }
            // Clean up transient playback file if any
            let tempFile = self.playbackTempDirectory.appendingPathComponent("\(safeId).m4a")
            try? self.fileManager.removeItem(at: tempFile)
            
            // Clean up extracted artwork
            let artFile = self.artworkDirectory.appendingPathComponent("\(safeId).jpg")
            try? self.fileManager.removeItem(at: artFile)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AudioPlayerEngine.trackDidCacheNotification, object: safeId)
            AIPlaylistEngine.shared.handleTrackRemoved(videoId: safeId)
        }
    }
    
    /// Synchronously and completely clears the offline audio library
    public func clearCache() {
        queue.sync {
            try? self.fileManager.removeItem(at: self.libraryDirectory)
            try? self.fileManager.removeItem(at: self.playbackTempDirectory)
            try? self.fileManager.removeItem(at: self.artworkDirectory)
            self.cachedManifest.removeAll()
            self.cachedTracksMetadata.removeAll()
            self.cachedIdsSet.removeAll()
            self.setupDirectories(force: true)
            self.saveManifest()
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AudioPlayerEngine.trackDidCacheNotification, object: nil)
        }
    }
    
    // MARK: - Storage Allocation Quota
    
    public static let storageLimitKey = "SonoristMaxStorageLimitGB"
    
    public var maxStorageLimitGB: Double {
        get {
            let val = UserDefaults.standard.double(forKey: Self.storageLimitKey)
            return val > 0 ? val : 5.0 // Default 5 GB
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.storageLimitKey)
        }
    }
    
    public var maxStorageLimitBytes: Int64 {
        Int64(maxStorageLimitGB * 1024 * 1024 * 1024)
    }
    
    private func internalGetCacheSizeBytes() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files where file.pathExtension == "sonorist" || file.pathExtension == "m4a" || file.pathExtension == "webm" {
            if let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    private func pruneCacheIfNeeded(incomingBytes: Int64) {
        let current = internalGetCacheSizeBytes()
        guard current + incomingBytes > maxStorageLimitBytes else { return }
        
        guard let files = try? fileManager.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        
        let sorted = files.sorted { f1, f2 in
            let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 < d2
        }
        
        var freed: Int64 = 0
        let targetToFree = (current + incomingBytes) - maxStorageLimitBytes
        
        for file in sorted {
            guard freed < targetToFree else { break }
            let name = file.lastPathComponent
            if let vid = cachedManifest.first(where: { $0.value == name })?.key {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                try? fileManager.removeItem(at: file)
                cachedManifest.removeValue(forKey: vid)
                cachedIdsSet.remove(vid)
                cachedTracksMetadata.removeValue(forKey: vid)
                freed += Int64(size)
            }
        }
        saveManifest()
    }
    
    // MARK: - Metrics & Navigation
    
    /// Calculates the total size of cached media files on disk
    public func getCacheSizeBytes() -> Int64 {
        return queue.sync {
            internalGetCacheSizeBytes()
        }
    }
    
    /// Returns a human-readable string of cache size (e.g. "0 KB" or "18.4 MB")
    public func getFormattedCacheSize() -> String {
        let bytes = getCacheSizeBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    #if os(macOS)
    /// Reveals the parent Sonorist folder in Finder
    public func revealParentFolderInFinder() {
        setupDirectories()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parentDirectory.path)
    }
    #endif
}

// MARK: - In-Memory Hardware-Accelerated Artwork Image Cache

/// Thread-safe in-memory cache for track artwork images.
/// Pre-warms incoming and adjacent track covers to eliminate render lag,
/// blank placeholder flickering, and main-thread disk decode stalls during transitions.
public final class ArtworkImageCache: ObservableObject, @unchecked Sendable {
    public static let shared = ArtworkImageCache()
    @Published public var cacheRevision: Int = 0
    
    private let cache = NSCache<NSURL, PlatformImage>()
    private let session: URLSession
    private let syncQueue = DispatchQueue(label: "com.sonorist.artcache.queue")
    private var inFlightTasks: [URL: Task<PlatformImage?, Never>] = [:]
    
    private init() {
        cache.countLimit = 60
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        self.session = URLSession(configuration: config)
        
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clear()
        }
        #endif
    }
    
    public func clear() {
        cache.removeAllObjects()
        DispatchQueue.main.async {
            self.cacheRevision &+= 1
        }
    }
    
    /// Instant O(1) synchronous RAM lookup. Returns decoded PlatformImage if already in memory.
    public func image(for url: URL?) -> PlatformImage? {
        guard let url = url else { return nil }
        return cache.object(forKey: url as NSURL)
    }
    
    /// Pre-warms artwork in background so it's instantly available when swiping or switching tracks.
    public func preload(url: URL?) {
        guard let url = url else { return }
        if cache.object(forKey: url as NSURL) != nil { return }
        
        Task.detached(priority: .utility) { [weak self] in
            _ = await self?.loadImage(for: url)
        }
    }
    
    /// Asynchronously loads, decodes, and caches artwork from disk or network off the main thread.
    public func loadImage(for url: URL?) async -> PlatformImage? {
        guard let url = url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Coalesce concurrent duplicate requests
        var existingTask: Task<PlatformImage?, Never>?
        syncQueue.sync {
            existingTask = inFlightTasks[url]
        }
        if let existing = existingTask {
            return await existing.value
        }
        
        let newTask = Task<PlatformImage?, Never>.detached(priority: .userInitiated) { [weak self, session, url] () -> PlatformImage? in
            defer {
                self?.syncQueue.async {
                    self?.inFlightTasks.removeValue(forKey: url)
                }
            }
            
            // 1. Local disk file
            if url.isFileURL {
                #if canImport(UIKit)
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
                image.draw(at: .zero)
                let decoded = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
                self?.cache.setObject(decoded, forKey: url as NSURL)
                DispatchQueue.main.async { self?.cacheRevision &+= 1 }
                return decoded
                #elseif canImport(AppKit)
                guard let image = NSImage(contentsOfFile: url.path) else { return nil }
                self?.cache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async { self?.cacheRevision &+= 1 }
                return image
                #endif
            }
            
            // 2. Remote network URL
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                let (data, response) = try await session.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                
                #if canImport(UIKit)
                guard let image = UIImage(data: data) else { return nil }
                UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
                image.draw(at: .zero)
                let decoded = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
                self?.cache.setObject(decoded, forKey: url as NSURL)
                DispatchQueue.main.async { self?.cacheRevision &+= 1 }
                return decoded
                #elseif canImport(AppKit)
                guard let image = NSImage(data: data) else { return nil }
                self?.cache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async { self?.cacheRevision &+= 1 }
                return image
                #endif
            } catch {
                return nil
            }
        }
        
        syncQueue.sync {
            inFlightTasks[url] = newTask
        }
        
        return await newTask.value
    }
}
