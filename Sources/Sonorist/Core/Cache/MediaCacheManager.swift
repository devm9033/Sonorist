import Foundation
import AppKit
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
    
    private let manifestURL: URL
    private let queue = DispatchQueue(label: "com.sonorist.mac.cache", qos: .utility)
    
    private var cachedManifest: [String: String] = [:] // videoId -> local .sonorist filename
    private var cachedTracksMetadata: [String: Track] = [:] // videoId -> Track
    private var cachedIdsSet: Set<String> = []
    
    public init() {
        // Preferred: Sandboxed Application Support directory
        let defaultAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = defaultAppSupport.appendingPathComponent("Sonorist", isDirectory: true)
        
        // Defensive fallback: If Application Support is restricted in sandbox, use /tmp/Sonorist
        let baseDir: URL
        if (try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)) != nil &&
           fileManager.isWritableFile(atPath: appFolder.path) {
            baseDir = appFolder
        } else {
            baseDir = URL(fileURLWithPath: "/tmp/Sonorist", isDirectory: true)
            try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        
        self.parentDirectory = baseDir
        self.libraryDirectory = baseDir.appendingPathComponent("Library", isDirectory: true)
        self.exportsDirectory = baseDir.appendingPathComponent("Exports", isDirectory: true)
        self.historyDirectory = baseDir.appendingPathComponent("History", isDirectory: true)
        self.playbackTempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SonoristPlayback", isDirectory: true)
        self.manifestURL = libraryDirectory.appendingPathComponent("library_manifest.json")
        
        setupDirectories()
        migrateLegacyCacheIfNeeded()
        loadManifest()
    }
    
    private func setupDirectories() {
        try? fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: playbackTempDirectory, withIntermediateDirectories: true)
    }
    
    private func migrateLegacyCacheIfNeeded() {
        // Automatically migrate any legacy MetrolistMac cache files
        let defaultAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    
    /// Checks if a track is available offline (instant zero-IO lookup)
    public func isCached(videoId: String) -> Bool {
        return queue.sync {
            return cachedIdsSet.contains(videoId)
        }
    }
    
    /// Returns the local bundle file URL if cached
    public func cachedURL(for videoId: String) -> URL? {
        return queue.sync {
            guard let filename = cachedManifest[videoId] else { return nil }
            let fileURL = libraryDirectory.appendingPathComponent(filename)
            return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
        }
    }
    
    /// Prepares real-time in-memory playback for a .sonorist bundle
    public func preparePlaybackStream(for videoId: String) -> URL? {
        return queue.sync {
            guard let filename = cachedManifest[videoId] else { return nil }
            let bundleURL = libraryDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: bundleURL.path) else { return nil }
            
            // Ensure temp directory exists
            try? fileManager.createDirectory(at: playbackTempDirectory, withIntermediateDirectories: true)
            
            // Check if already extracted in temp directory
            let tempPlayURL = playbackTempDirectory.appendingPathComponent("\(videoId).m4a")
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
            guard let filename = cachedManifest[videoId], filename.hasSuffix(".sonorist") else { return nil }
            let bundleURL = libraryDirectory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: bundleURL),
                  let meta = try? SonoristBundleEngine.readMetadataOnly(from: data),
                  !meta.lyrics.isEmpty else { return nil }
            return meta.lyrics
        }
    }
    
    /// Returns all saved offline tracks from the compressed library
    public func getAllCachedTracks() -> [Track] {
        return queue.sync {
            var valid: [Track] = []
            for (vid, filename) in cachedManifest {
                let fileURL = libraryDirectory.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                
                // If it's a .sonorist bundle, read metadata in O(1) without decompressing audio
                if filename.hasSuffix(".sonorist") {
                    if let data = try? Data(contentsOf: fileURL),
                       let meta = try? SonoristBundleEngine.readMetadataOnly(from: data) {
                        var t = meta.track
                        t.isCached = true
                        t.streamURL = nil // Never set streamURL to the raw .sonorist bundle file
                        valid.append(t)
                        self.cachedTracksMetadata[vid] = t
                        continue
                    }
                }
                
                // Fallback to in-memory metadata
                if let track = cachedTracksMetadata[vid] {
                    var t = track
                    t.isCached = true
                    t.streamURL = nil // Never set streamURL to the raw .sonorist bundle file
                    valid.append(t)
                }
            }
            return valid
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
            do {
                let bundleData = try SonoristBundleEngine.pack(
                    track: track,
                    audioData: audioData,
                    lyrics: lyrics,
                    artworkData: artworkData
                )
                
                let filename = "\(track.id).sonorist"
                let destURL = self.libraryDirectory.appendingPathComponent(filename)
                try bundleData.write(to: destURL, options: .atomic)
                
                self.cachedManifest[track.id] = filename
                self.cachedIdsSet.insert(track.id)
                var t = track
                t.isCached = true
                self.cachedTracksMetadata[track.id] = t
                self.saveManifest()
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
                    trackName = meta != nil ? "\(meta!.artist) - \(meta!.title)" : vid
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
        queue.sync {
            if let filename = self.cachedManifest[videoId] {
                let fileURL = self.libraryDirectory.appendingPathComponent(filename)
                try? self.fileManager.removeItem(at: fileURL)
                self.cachedManifest.removeValue(forKey: videoId)
                self.cachedIdsSet.remove(videoId)
                self.cachedTracksMetadata.removeValue(forKey: videoId)
                self.saveManifest()
            }
            // Also clean up transient playback file if any
            let tempFile = self.playbackTempDirectory.appendingPathComponent("\(videoId).m4a")
            try? self.fileManager.removeItem(at: tempFile)
        }
    }
    
    /// Synchronously and completely clears the offline audio library
    public func clearCache() {
        queue.sync {
            try? self.fileManager.removeItem(at: self.libraryDirectory)
            try? self.fileManager.removeItem(at: self.playbackTempDirectory)
            self.cachedManifest.removeAll()
            self.cachedTracksMetadata.removeAll()
            self.cachedIdsSet.removeAll()
            self.setupDirectories()
            self.saveManifest()
        }
    }
    
    // MARK: - Metrics & Navigation
    
    /// Calculates the total size of cached media files on disk
    public func getCacheSizeBytes() -> Int64 {
        return queue.sync {
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
    }
    
    /// Returns a human-readable string of cache size (e.g. "0 KB" or "18.4 MB")
    public func getFormattedCacheSize() -> String {
        let bytes = getCacheSizeBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Reveals the parent Sonorist folder in Finder
    public func revealParentFolderInFinder() {
        setupDirectories()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parentDirectory.path)
    }
}
