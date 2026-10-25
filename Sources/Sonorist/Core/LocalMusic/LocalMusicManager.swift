import Foundation
import AVFoundation
import AppKit

/// Local Music Manager enabling Sonorist to act as a clean, fast offline music player
/// Handles local file imports, ID3/QuickTime metadata parsing, and offline library indexing.
@MainActor
public final class LocalMusicManager: ObservableObject {
    public static let shared = LocalMusicManager()
    
    @Published public var localTracks: [Track] = []
    @Published public var isImporting: Bool = false
    
    private let fileManager = FileManager.default
    private let libraryManifestURL: URL
    private let artworkCacheDir: URL
    
    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Sonorist", isDirectory: true)
        
        if fileManager.isWritableFile(atPath: appFolder.path) {
            self.libraryManifestURL = appFolder.appendingPathComponent("local_library.json")
            self.artworkCacheDir = appFolder.appendingPathComponent("LocalArtwork", isDirectory: true)
        } else {
            let fallback = URL(fileURLWithPath: "/tmp/Sonorist", isDirectory: true)
            self.libraryManifestURL = fallback.appendingPathComponent("local_library.json")
            self.artworkCacheDir = fallback.appendingPathComponent("LocalArtwork", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: artworkCacheDir, withIntermediateDirectories: true)
        loadLibrary()
    }
    
    // MARK: - Open Panel File Picker
    
    /// Presents a native macOS NSOpenPanel to import audio files or directories
    public func promptForImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .mpeg4Audio,
            .wav
        ]
        panel.title = "Import Music to Sonorist"
        panel.message = "Choose audio files or folders to add to your offline library"
        panel.prompt = "Import"
        
        if panel.runModal() == .OK {
            isImporting = true
            let urls = panel.urls
            Task {
                await self.importURLs(urls)
                self.isImporting = false
            }
        }
    }
    
    /// Imports an array of file/folder URLs recursively
    public func importURLs(_ urls: [URL]) async {
        var filesToProcess: [URL] = []
        let supportedExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "aac", "aiff"]
        
        for url in urls {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let subpaths = try? fileManager.subpathsOfDirectory(atPath: url.path) {
                        for sub in subpaths {
                            let fileURL = url.appendingPathComponent(sub)
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                filesToProcess.append(fileURL)
                            }
                        }
                    }
                } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    filesToProcess.append(url)
                }
            }
        }
        
        for file in filesToProcess {
            if let track = await extractMetadata(from: file) {
                if !localTracks.contains(where: { $0.id == track.id }) {
                    localTracks.append(track)
                }
            }
        }
        
        saveLibrary()
    }
    
    /// Extracts track title, artist, album, duration, and cover art using AVURLAsset
    private func extractMetadata(from fileURL: URL) async -> Track? {
        let asset = AVURLAsset(url: fileURL)
        let id = "local_\(fileURL.path.hashValue)"
        
        var title = fileURL.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var artworkURL: URL? = nil
        
        // Extract common metadata
        do {
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata {
                if let key = item.commonKey?.rawValue {
                    switch key {
                    case "title":
                        if let str = try? await item.load(.stringValue), !str.isEmpty {
                            title = str
                        }
                    case "artist", "author":
                        if let str = try? await item.load(.stringValue), !str.isEmpty {
                            artist = str
                        }
                    case "albumName":
                        if let str = try? await item.load(.stringValue), !str.isEmpty {
                            album = str
                        }
                    case "artwork":
                        if let data = try? await item.load(.dataValue) {
                            let artFile = artworkCacheDir.appendingPathComponent("\(id).jpg")
                            try? data.write(to: artFile)
                            artworkURL = artFile
                        }
                    default:
                        break
                    }
                }
            }
            
            let durationSeconds: Double
            if let duration = try? await asset.load(.duration) {
                durationSeconds = duration.seconds.isFinite ? duration.seconds : 0
            } else {
                durationSeconds = 0
            }
            
            return Track(
                id: id,
                title: title,
                artist: artist,
                album: album,
                durationSeconds: durationSeconds,
                artworkURL: artworkURL,
                streamURL: fileURL,
                audioFormat: "Local (\(fileURL.pathExtension.uppercased()))",
                isLiked: false,
                isCached: true
            )
        } catch {
            return nil
        }
    }
    
    public func removeTrack(id: String) {
        localTracks.removeAll(where: { $0.id == id })
        saveLibrary()
    }
    
    public func clearLocalLibrary() {
        localTracks.removeAll()
        saveLibrary()
    }
    
    // MARK: - Persistence
    
    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(localTracks) {
            try? data.write(to: libraryManifestURL, options: .atomic)
        }
    }
    
    private func loadLibrary() {
        if let data = try? Data(contentsOf: libraryManifestURL),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            // Verify files still exist on disk
            self.localTracks = tracks.filter { track in
                guard let url = track.streamURL else { return false }
                return fileManager.fileExists(atPath: url.path)
            }
        }
    }
}
