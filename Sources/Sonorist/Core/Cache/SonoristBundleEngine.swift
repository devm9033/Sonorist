import Foundation
import Compression

/// Represents an unpacked Sonorist compressed container
public struct SonoristBundle: Sendable {
    public let track: Track
    public let lyrics: [LyricLine]
    public let artworkData: Data?
    public let audioData: Data
    public let rawAudioSize: Int
    public let compressedAudioSize: Int
    
    public init(
        track: Track,
        lyrics: [LyricLine],
        artworkData: Data?,
        audioData: Data,
        rawAudioSize: Int,
        compressedAudioSize: Int
    ) {
        self.track = track
        self.lyrics = lyrics
        self.artworkData = artworkData
        self.audioData = audioData
        self.rawAudioSize = rawAudioSize
        self.compressedAudioSize = compressedAudioSize
    }
}

/// High-performance binary packaging and Apple LZFSE compression engine
/// Bundles audio stream, rich metadata, album art, and millisecond-accurate synchronized lyrics into a single proprietary .sonorist file.
public enum SonoristBundleEngine {
    private static let magicHeader = "SONORIST".data(using: .utf8)! // 8 bytes
    private static let currentVersion: UInt16 = 1                   // 2 bytes
    
    // MARK: - Packing
    
    /// Packs track metadata, synced lyrics, album artwork, and raw audio into a compressed .sonorist binary payload
    public static func pack(
        track: Track,
        audioData: Data,
        lyrics: [LyricLine] = [],
        artworkData: Data? = nil
    ) throws -> Data {
        var payload = Data()
        
        // 1. Magic Header & Version
        payload.append(magicHeader)
        var version = currentVersion.littleEndian
        payload.append(Data(bytes: &version, count: MemoryLayout<UInt16>.size))
        
        // 2. Metadata Chunk (JSON)
        let metaJSON = try JSONEncoder().encode(track)
        var metaLen = UInt32(metaJSON.count).littleEndian
        payload.append(Data(bytes: &metaLen, count: MemoryLayout<UInt32>.size))
        payload.append(metaJSON)
        
        // 3. Synced Lyrics Chunk (JSON)
        let lyricsJSON = try JSONEncoder().encode(lyrics)
        var lyricsLen = UInt32(lyricsJSON.count).littleEndian
        payload.append(Data(bytes: &lyricsLen, count: MemoryLayout<UInt32>.size))
        payload.append(lyricsJSON)
        
        // 4. Artwork Chunk (Image Data)
        let artData = artworkData ?? Data()
        var artLen = UInt32(artData.count).littleEndian
        payload.append(Data(bytes: &artLen, count: MemoryLayout<UInt32>.size))
        payload.append(artData)
        
        // 5. Audio Chunk (Compressed with Apple LZFSE)
        var rawAudioSize = UInt32(audioData.count).littleEndian
        let compressedAudio = compressLZFSE(data: audioData) ?? audioData
        var compAudioSize = UInt32(compressedAudio.count).littleEndian
        
        payload.append(Data(bytes: &rawAudioSize, count: MemoryLayout<UInt32>.size))
        payload.append(Data(bytes: &compAudioSize, count: MemoryLayout<UInt32>.size))
        payload.append(compressedAudio)
        
        return payload
    }
    
    // MARK: - Unpacking
    
    /// Fully unpacks a .sonorist container, decompressing the audio into memory
    public static func unpack(data: Data) throws -> SonoristBundle {
        var offset = 0
        
        // Verify Magic
        guard data.count >= 10 else {
            throw NSError(domain: "SonoristBundleEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid file size."])
        }
        let magic = data.subdata(in: 0..<8)
        guard magic == magicHeader else {
            throw NSError(domain: "SonoristBundleEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid container magic header."])
        }
        offset += 8
        
        // Version
        let version: UInt16 = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        guard version == currentVersion else {
            throw NSError(domain: "SonoristBundleEngine", code: 402, userInfo: [NSLocalizedDescriptionKey: "Unsupported container version: \(version)"])
        }
        offset += 2
        
        // Metadata
        let metaLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let metaData = data.subdata(in: offset..<(offset + Int(metaLen)))
        let track = try JSONDecoder().decode(Track.self, from: metaData)
        offset += Int(metaLen)
        
        // Lyrics
        let lyricsLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let lyricsData = data.subdata(in: offset..<(offset + Int(lyricsLen)))
        let decodedLyrics: [LyricLine] = (try? JSONDecoder().decode([LyricLine].self, from: lyricsData)) ?? []
        offset += Int(lyricsLen)
        
        // Artwork
        let artLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let artworkData = artLen > 0 ? data.subdata(in: offset..<(offset + Int(artLen))) : nil
        offset += Int(artLen)
        
        // Audio
        let rawAudioSize: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let compAudioSize: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        
        let compressedAudioData = data.subdata(in: offset..<(offset + Int(compAudioSize)))
        let decompressedAudio = decompressLZFSE(data: compressedAudioData, uncompressedSize: Int(rawAudioSize)) ?? compressedAudioData
        
        return SonoristBundle(
            track: track,
            lyrics: decodedLyrics,
            artworkData: artworkData,
            audioData: decompressedAudio,
            rawAudioSize: Int(rawAudioSize),
            compressedAudioSize: Int(compAudioSize)
        )
    }
    
    // MARK: - Fast Metadata Only Lookup (Zero Audio Decompression)
    
    /// Reads track and lyrics metadata in O(1) time without decompressing the multi-megabyte audio stream
    public static func readMetadataOnly(from data: Data) throws -> (track: Track, lyrics: [LyricLine], artworkData: Data?) {
        guard data.count >= 18 else {
            throw NSError(domain: "SonoristBundleEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Corrupted bundle: too short."])
        }
        let magic = data.subdata(in: 0..<8)
        guard magic == magicHeader else {
            throw NSError(domain: "SonoristBundleEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid container magic."])
        }
        
        var offset = 10 // Magic (8) + Version (2)
        
        // Metadata
        let metaLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let metaData = data.subdata(in: offset..<(offset + Int(metaLen)))
        let track = try JSONDecoder().decode(Track.self, from: metaData)
        offset += Int(metaLen)
        
        // Lyrics
        let lyricsLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let lyricsData = data.subdata(in: offset..<(offset + Int(lyricsLen)))
        let decodedLyrics: [LyricLine] = (try? JSONDecoder().decode([LyricLine].self, from: lyricsData)) ?? []
        offset += Int(lyricsLen)
        
        // Artwork
        let artLen: UInt32 = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        let artworkData = artLen > 0 ? data.subdata(in: offset..<(offset + Int(artLen))) : nil
        
        return (track, decodedLyrics, artworkData)
    }
    
    // MARK: - Apple LZFSE Compression Primitives
    
    /// Compresses a buffer using Apple's high-speed LZFSE algorithm
    public static func compressLZFSE(data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        
        let destinationCapacity = data.count + 512
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
        defer { destinationBuffer.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                destinationCapacity,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }
        
        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
    
    /// Decompresses an LZFSE buffer into memory
    public static func decompressLZFSE(data: Data, uncompressedSize: Int) -> Data? {
        guard !data.isEmpty, uncompressedSize > 0 else { return Data() }
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }
        
        let decompressedSize = data.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                uncompressedSize,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }
        
        guard decompressedSize == uncompressedSize else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}
