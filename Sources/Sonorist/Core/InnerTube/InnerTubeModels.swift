import Foundation

public enum AudioQuality: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto (Best Quality)"
    case high = "High (Opus 160kbps)"
    case standard = "Standard (AAC 128kbps)"
    case dataSaver = "Data Saver (AAC 48kbps)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "Opus 160k"
        case .standard: return "AAC 128k"
        case .dataSaver: return "AAC 48k"
        }
    }
}

public struct AudioStreamOption: Identifiable, Hashable, Codable {
    public let id: String
    public let quality: AudioQuality
    public let itag: Int
    public let mimeType: String
    public let bitrate: Int
    public let label: String
    
    public init(id: String = UUID().uuidString, quality: AudioQuality, itag: Int, mimeType: String, bitrate: Int, label: String) {
        self.id = id
        self.quality = quality
        self.itag = itag
        self.mimeType = mimeType
        self.bitrate = bitrate
        self.label = label
    }
}

/// Model representing a playable track in Sonorist
public struct Track: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Double
    public var artworkURL: URL?
    public var streamURL: URL?
    public var audioFormat: String
    public var isLiked: Bool
    public var isCached: Bool
    
    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double = 0,
        artworkURL: URL? = nil,
        streamURL: URL? = nil,
        audioFormat: String = "AAC 128kbps",
        isLiked: Bool = false,
        isCached: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.audioFormat = audioFormat
        self.isLiked = isLiked
        self.isCached = isCached
    }
    
    public var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - InnerTube Stream Extraction Response Types

public struct InnerTubePlayerResponse: Decodable {
    public let playabilityStatus: PlayabilityStatus?
    public let videoDetails: VideoDetails?
    public let streamingData: StreamingData?
    
    public struct PlayabilityStatus: Decodable {
        public let status: String?
        public let reason: String?
    }
    
    public struct VideoDetails: Decodable {
        public let videoId: String?
        public let title: String?
        public let lengthSeconds: String?
        public let author: String?
        public let shortDescription: String?
        public let thumbnail: ThumbnailContainer?
    }
    
    public struct ThumbnailContainer: Decodable {
        public let thumbnails: [ThumbnailItem]?
    }
    
    public struct ThumbnailItem: Decodable {
        public let url: String
        public let width: Int?
        public let height: Int?
    }
    
    public struct StreamingData: Decodable {
        public let expiresInSeconds: String?
        public let formats: [FormatItem]?
        public let adaptiveFormats: [FormatItem]?
    }
    
    public struct FormatItem: Decodable {
        public let itag: Int
        public let url: String?
        public let mimeType: String?
        public let bitrate: Int?
        public let averageBitrate: Int?
        public let contentLength: String?
        public let audioQuality: String?
        public let signatureCipher: String?
        public let cipher: String?
    }
}
