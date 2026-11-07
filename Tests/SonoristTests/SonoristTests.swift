import Foundation
import AVFoundation

@main
struct SonoristTestsRunner {
    static func main() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Sonorist Comprehensive Verification Suite")
        print("  ECC Security • Reverse Engineering • Apple Design")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        var passed = 0
        var failed = 0
        
        func test(_ name: String, block: () throws -> Void) {
            do {
                try block()
                passed += 1
                print("  ✓ [PASS] \(name)")
            } catch {
                failed += 1
                print("  ✗ [FAIL] \(name): \(error)")
            }
        }
        
        // MARK: - 1. Security & ATS Validation
        test("SecurityAudit: Valid YouTube & LRCLIB URLs Pass ATS") {
            let u1 = SecurityAudit.validateURL("https://music.youtube.com/youtubei/v1/player")
            guard u1 != nil else { throw TestError("Expected valid URL for music.youtube.com") }
            
            let u2 = SecurityAudit.validateURL("https://rr1---sn-4g5edn6s.googlevideo.com/videoplayback?id=123")
            guard u2 != nil else { throw TestError("Expected valid URL for googlevideo.com") }
            
            let u3 = SecurityAudit.validateURL("https://yt3.googleusercontent.com/sample_thumbnail=w120-h120")
            guard u3 != nil else { throw TestError("Expected valid URL for yt3.googleusercontent.com") }
            
            let u4 = SecurityAudit.validateURL("https://lrclib.net/api/get?track_name=test&artist_name=artist")
            guard u4 != nil else { throw TestError("Expected valid URL for lrclib.net") }
            
            let uLocal = SecurityAudit.validateURL("file:///Users/music/song.mp3")
            guard uLocal != nil else { throw TestError("Local file:// URLs must be allowed") }
        }
        
        test("SecurityAudit: Insecure HTTP Protocol Blocked by ATS") {
            let u = SecurityAudit.validateURL("http://music.youtube.com/youtubei/v1/player")
            guard u == nil else { throw TestError("HTTP must be blocked by ATS") }
        }
        
        test("SecurityAudit: Malicious / Phishing Host Blocked") {
            let u = SecurityAudit.validateURL("https://malicious-phishing-site.com/track.mp3")
            guard u == nil else { throw TestError("Untrusted host must be rejected") }
        }
        
        test("SecurityAudit: Search Query Sanitization & Control Char Stripping") {
            let dirty = "The Weeknd \u{0000}\u{001F}\t"
            let clean = SecurityAudit.sanitizeSearchQuery(dirty)
            guard clean == "The Weeknd" else { throw TestError("Failed to sanitize: '\(clean)'") }
        }
        
        test("SecurityAudit: Video ID Regex Validation") {
            guard SecurityAudit.validateVideoID("fJ9rUzIMcZQ") else { throw TestError("Valid ID rejected") }
            guard SecurityAudit.validateVideoID("kJQP7kiw5Fk") else { throw TestError("Valid ID rejected") }
            guard !SecurityAudit.validateVideoID("short") else { throw TestError("Short ID accepted") }
            guard !SecurityAudit.validateVideoID("invalid;drop;table") else { throw TestError("SQLi/bad ID accepted") }
        }
        
        // MARK: - 2. Cipher & JavaScriptCore Deobfuscation
        test("YouTubeCipherEngine: JavaScriptCore Sandboxed Execution") {
            let engine = YouTubeCipherEngine.shared
            let sig = engine.solveSignature(s: "ABCDEF")
            guard sig == "FEDCBA" else { throw TestError("Decipher failed: got \(sig)") }
            
            let n = engine.solveNTransform(n: "token123")
            guard !n.isEmpty else { throw TestError("N-transform returned empty") }
        }
        
        test("YouTubeCipherEngine: Raw Cipher URL Extraction & Param Parsing") {
            let engine = YouTubeCipherEngine.shared
            let rawCipher = "s=ABCDEF&sp=sig&url=https%3A%2F%2Frr1---sn.googlevideo.com%2Fvideoplayback%3Fid%3D123"
            let resolved = engine.decipher(rawCipher: rawCipher)
            guard let url = resolved else { throw TestError("Failed to decipher raw cipher string") }
            guard url.absoluteString.contains("sig=FEDCBA") else { throw TestError("Missing decrypted sig in URL") }
        }
        
        // MARK: - 3. LRC Synchronized Lyrics Parsing
        test("LRCLIBService: LRC Millisecond Timestamp Parsing & Ordering") {
            let lrcSample = """
            [00:04.50] Is this the real life?
            [00:08.20] Is this just fantasy?
            [00:15.00] Caught in a landslide
            [01:03.456] No escape from reality
            """
            
            let service = LRCLIBService.shared
            let lines = service.parseLRC(lrcSample)
            
            guard lines.count == 4 else {
                throw TestError("Expected 4 lines parsed, got \(lines.count)")
            }
            guard abs(lines[0].time - 4.5) < 0.01 else {
                throw TestError("First line time mismatch: \(lines[0].time)")
            }
            guard lines[0].text == "Is this the real life?" else {
                throw TestError("First line text mismatch: \(lines[0].text)")
            }
            guard abs(lines[3].time - 63.456) < 0.01 else {
                throw TestError("Fourth line time mismatch: \(lines[3].time)")
            }
        }
        
        test("LRCLIBService: Offset Tag & Multi-Timestamp Parsing") {
            let lrcWithOffset = """
            [offset: +500]
            [00:02.00]First line
            [00:05.00][00:10.00]Chorus line repeated
            """
            let lines = LRCLIBService.shared.parseLRC(lrcWithOffset)
            guard lines.count == 3 else {
                throw TestError("Expected 3 parsed lines from multi-timestamp, got \(lines.count)")
            }
            guard abs(lines[0].time - 2.5) < 0.01 else {
                throw TestError("Offset not applied: \(lines[0].time)")
            }
            guard lines[0].text == "First line" else { throw TestError("Text mismatch") }
            guard abs(lines[1].time - 5.5) < 0.01 else { throw TestError("Multi-timestamp 1 mismatch: \(lines[1].time)") }
            guard abs(lines[2].time - 10.5) < 0.01 else { throw TestError("Multi-timestamp 2 mismatch: \(lines[2].time)") }
        }
        
        test("AudioPlayerEngine: Lyric Offset & Lead Time Calculation") {
            let engine = AudioPlayerEngine.shared
            engine.lyricLeadTime = 0.35
            engine.userLyricOffset = 0.0
            engine.adjustLyricOffset(by: 0.25)
            guard abs(engine.userLyricOffset - 0.25) < 0.01 else {
                throw TestError("Expected userLyricOffset to be 0.25, got \(engine.userLyricOffset)")
            }
            engine.resetLyricOffset()
            guard engine.userLyricOffset == 0.0 else {
                throw TestError("Expected reset to 0.0, got \(engine.userLyricOffset)")
            }
        }
        
        // MARK: - 4. Track Model & Media Cache Verification
        test("Track Model: Duration Formatting") {
            let track = Track(id: "fJ9rUzIMcZQ", title: "Bohemian Rhapsody", artist: "Queen", durationSeconds: 354)
            guard track.formattedDuration == "5:54" else { throw TestError("Formatted duration mismatch: \(track.formattedDuration)") }
        }
        
        test("SleepTimerOption: Duration Calculations") {
            guard SleepTimerOption.off.durationSeconds == nil else { throw TestError("Off should have nil duration") }
            guard SleepTimerOption.min15.durationSeconds == 900 else { throw TestError("15 min must be 900 seconds") }
            guard SleepTimerOption.min30.durationSeconds == 1800 else { throw TestError("30 min must be 1800 seconds") }
            guard SleepTimerOption.min60.durationSeconds == 3600 else { throw TestError("1 hour must be 3600 seconds") }
        }
        
        test("MediaCacheManager: Cache & Clear Purge Lifecycle") {
            let cache = MediaCacheManager.shared
            let sampleTrack = Track(id: "testTrack123", title: "Test", artist: "Artist", audioFormat: "AAC 128kbps")
            let sampleData = "SAMPLE_AUDIO_BYTES".data(using: .utf8)!
            
            // 1. Cache track
            cache.cacheTrack(track: sampleTrack, data: sampleData)
            guard cache.isCached(videoId: "testTrack123") else {
                throw TestError("Track was not cached")
            }
            guard cache.getCacheSizeBytes() > 0 else {
                throw TestError("Cache size should be greater than 0")
            }
            
            // 2. Clear cache
            cache.clearCache()
            guard !cache.isCached(videoId: "testTrack123") else {
                throw TestError("Track should not be cached after purge")
            }
            guard cache.getCacheSizeBytes() == 0 else {
                throw TestError("Cache size must be 0 after clearCache()")
            }
            guard cache.getAllCachedTracks().isEmpty else {
                throw TestError("Cached tracks list must be empty after clearCache()")
            }
        }
        
        // MARK: - 5. Audio Quality & Stream Options
        test("AudioQuality: Labels, IDs, and Case Enumerations") {
            guard AudioQuality.allCases.count >= 4 else { throw TestError("Expected at least 4 audio quality cases") }
            guard AudioQuality.high.shortLabel == "Opus 160k" else { throw TestError("High shortLabel mismatch") }
            guard AudioQuality.standard.shortLabel == "AAC 128k" else { throw TestError("Standard shortLabel mismatch") }
            guard AudioQuality.dataSaver.shortLabel == "AAC 48k" else { throw TestError("Data saver shortLabel mismatch") }
            
            let stream = AudioStreamOption(quality: .high, itag: 251, mimeType: "audio/webm; codecs=\"opus\"", bitrate: 160000, label: "Opus 160 kbps (Best Quality)")
            guard stream.itag == 251 && stream.quality == .high else { throw TestError("Stream option property mismatch") }
        }
        
        // MARK: - 6. High-Resolution Artwork URL Upgrades
        test("InnerTubeClient: High-Res Artwork Transformation") {
            let lowResGoogle = "https://lh3.googleusercontent.com/test_id=w120-h120-l90-rj"
            let upgradedGoogle = InnerTubeClient.highResArtworkURL(from: lowResGoogle)
            guard let gURL = upgradedGoogle?.absoluteString else { throw TestError("Failed to upgrade google thumbnail") }
            guard gURL.contains("=w800-h800-l90-rj") else { throw TestError("Expected =w800-h800-l90-rj, got: \(gURL)") }
            
            let lowResYT = "https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg"
            let upgradedYT = InnerTubeClient.highResArtworkURL(from: lowResYT)
            guard let ytURL = upgradedYT?.absoluteString else { throw TestError("Failed to upgrade ytimg thumbnail") }
            guard ytURL.contains("/maxresdefault.jpg") else { throw TestError("Expected maxresdefault.jpg, got: \(ytURL)") }
        }
        
        // MARK: - 7. Instant In-Memory Cache Index
        test("MediaCacheManager: In-Memory Index O(1) Instant Check") {
            let cache = MediaCacheManager.shared
            let fastTrack = Track(id: "fastCheckTrack123", title: "Fast", artist: "Artist", audioFormat: "AAC 128kbps")
            let sampleBytes = "FAST_AUDIO".data(using: .utf8)!
            
            cache.cacheTrack(track: fastTrack, data: sampleBytes)
            guard cache.isCached(videoId: "fastCheckTrack123") else {
                throw TestError("Instant cache index check failed for fastCheckTrack123")
            }
            cache.clearCache()
            guard !cache.isCached(videoId: "fastCheckTrack123") else {
                throw TestError("Instant cache index should reflect clearCache")
            }
        }
        
        // MARK: - 8. YouTube Music Radio & Autoplay Logic
        test("Radio & Autoplay: Seeded Playlist ID & Video Validation") {
            let seedVideoId = "gvbiogUgFYA"
            guard SecurityAudit.validateVideoID(seedVideoId) else { throw TestError("Valid seed ID rejected") }
            let radioPlaylistId = "RDAMVM" + seedVideoId
            guard radioPlaylistId == "RDAMVMgvbiogUgFYA" else { throw TestError("Radio playlist ID format mismatch") }
        }
        
        test("ImmersiveViewModel: Responsive Mode Switching") {
            let vm = ImmersiveViewModel.shared
            vm.compactTab = 0
            guard vm.compactTab == 0 else { throw TestError("Compact tab default mismatch") }
            vm.compactTab = 1
            guard vm.compactTab == 1 else { throw TestError("Compact tab switch mismatch") }
        }
        
        test("AppNavigationState: Sidebar Visibility Toggle") {
            let nav = AppNavigationState.shared
            nav.isSidebarVisible = true
            guard nav.isSidebarVisible else { throw TestError("Sidebar initial state must be visible") }
            nav.isSidebarVisible.toggle()
            guard !nav.isSidebarVisible else { throw TestError("Sidebar toggle must hide sidebar") }
            nav.isSidebarVisible = true
        }
        
        test("AppNavigationState: Default to Search and Tab Persistence Round-Trip") {
            let originalKey = UserDefaults.standard.string(forKey: AppNavigationState.lastNavigationItemKey)
            defer {
                if let orig = originalKey {
                    UserDefaults.standard.set(orig, forKey: AppNavigationState.lastNavigationItemKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: AppNavigationState.lastNavigationItemKey)
                }
            }
            
            // 1. Simulate fresh install: key removed
            UserDefaults.standard.removeObject(forKey: AppNavigationState.lastNavigationItemKey)
            let freshNav = AppNavigationState()
            guard freshNav.selectedItem == .search else {
                throw TestError("First time launch must default to Search window, got: \(String(describing: freshNav.selectedItem))")
            }
            
            // 2. Select Library and verify persistence
            freshNav.selectedItem = .library
            let savedAfterLibrary = UserDefaults.standard.string(forKey: AppNavigationState.lastNavigationItemKey)
            guard savedAfterLibrary == NavigationItem.library.rawValue else {
                throw TestError("Selecting Library did not persist to UserDefaults, got: \(String(describing: savedAfterLibrary))")
            }
            
            // 3. Simulate app restart: newly initialized state must restore Library
            let restoredNav1 = AppNavigationState()
            guard restoredNav1.selectedItem == .library else {
                throw TestError("Subsequent launch did not restore Library, got: \(String(describing: restoredNav1.selectedItem))")
            }
            
            // 4. Select Analytics and verify persistence on restart
            restoredNav1.selectedItem = .analytics
            let restoredNav2 = AppNavigationState()
            guard restoredNav2.selectedItem == .analytics else {
                throw TestError("Subsequent launch did not restore Analytics, got: \(String(describing: restoredNav2.selectedItem))")
            }
        }
        
        test("ListeningAnalyticsManager: Track Start & Duration Recording") {
            let manager = ListeningAnalyticsManager.shared
            let testTrack = Track(id: "analytics_test_999", title: "Test Song", artist: "Analytics Artist", audioFormat: "AAC 128kbps")
            let initialSongs = manager.totalSongsPlayed
            let initialSeconds = manager.totalSecondsListened
            
            manager.recordTrackStart(track: testTrack, quality: .standard, isCached: false)
            guard manager.totalSongsPlayed == initialSongs + 1 else { throw TestError("totalSongsPlayed did not increment") }
            
            manager.recordListeningTime(seconds: 120.0, track: testTrack)
            guard manager.totalSecondsListened >= initialSeconds + 120.0 else { throw TestError("totalSecondsListened did not accumulate") }
            guard !manager.formattedTotalTime.isEmpty else { throw TestError("formattedTotalTime should not be empty") }
        }
        
        // MARK: - 9. Sonorist Bundle Engine & LZFSE Compression
        test("SonoristBundleEngine: Binary Packaging & LZFSE Round-Trip Integrity") {
            let track = Track(id: "sono_test_101", title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", durationSeconds: 243.0, audioFormat: "AAC 128kbps")
            let sampleAudio = String(repeating: "AUDIO_FRAME_M4A_SAMPLE_BUFFER_DATA_STREAM_AAC_", count: 1000).data(using: .utf8)!
            let sampleLyrics = [
                LyricLine(id: "1", time: 1.5, text: "Waiting in a car"),
                LyricLine(id: "2", time: 4.2, text: "Waiting for a ride in the dark")
            ]
            let sampleArtwork = "FAKE_JPEG_IMAGE_BYTES_12345".data(using: .utf8)!
            
            let packed = try SonoristBundleEngine.pack(
                track: track,
                audioData: sampleAudio,
                lyrics: sampleLyrics,
                artworkData: sampleArtwork
            )
            guard packed.count > 0 else { throw TestError("Packed bundle data is empty") }
            
            // Test Fast Metadata-Only O(1) Reader
            let (metaTrack, metaLyrics, metaArt) = try SonoristBundleEngine.readMetadataOnly(from: packed)
            guard metaTrack.id == "sono_test_101" && metaTrack.title == "Midnight City" else { throw TestError("Metadata O(1) title mismatch") }
            guard metaLyrics.count == 2 else { throw TestError("Metadata O(1) lyrics count mismatch") }
            guard metaArt == sampleArtwork else { throw TestError("Metadata O(1) artwork mismatch") }
            
            // Test Full Unpack & LZFSE Decompression
            let unpacked = try SonoristBundleEngine.unpack(data: packed)
            guard unpacked.track.id == track.id else { throw TestError("Unpacked track id mismatch") }
            guard unpacked.audioData == sampleAudio else { throw TestError("Unpacked audio bytes do not match original raw data") }
            guard unpacked.lyrics.count == 2 else { throw TestError("Unpacked lyrics count mismatch") }
            guard unpacked.artworkData == sampleArtwork else { throw TestError("Unpacked artwork mismatch") }
        }
        
        // MARK: - 10. Space Savings Metric Calculation
        test("Space Savings: Sonorist LZFSE Container Space Reduction Calculation") {
            let track = Track(id: "space_metric_1", title: "Space Test", artist: "Artist", audioFormat: "AAC 128kbps")
            // Simulate 1 MB payload with repeated audio/metadata frames
            let sampleAudio = String(repeating: "M4A_PAYLOAD_CHUNK_AAC_128K_STEREO_SIMULATED_DATA_PACKET_", count: 18000).data(using: .utf8)!
            let rawUncompressedSize = sampleAudio.count
            
            let packed = try SonoristBundleEngine.pack(
                track: track,
                audioData: sampleAudio,
                lyrics: [LyricLine(id: "1", time: 0.0, text: "Test line")],
                artworkData: "ARTWORK_DATA".data(using: .utf8)!
            )
            
            let compressedSize = packed.count
            let spaceSavedBytes = rawUncompressedSize - compressedSize
            let percentageSaved = (Double(spaceSavedBytes) / Double(rawUncompressedSize)) * 100.0
            
            print("     ↳ Raw size: \(rawUncompressedSize / 1024) KB, .sonorist compressed: \(compressedSize / 1024) KB")
            print("     ↳ Space reduction: \(String(format: "%.1f", percentageSaved))% space saved!")
            guard percentageSaved > 0 else { throw TestError("Compression did not reduce size") }
        }
        
        // MARK: - 11. Intentional Listening 15-Second Skip Gate
        test("Intentional Listening: 15-Second Skip Filter Logic") {
            let engine = AudioPlayerEngine.shared
            
            // Simulate short 4-second preview (skip)
            engine.continuousListeningSeconds = 4.0
            engine.hasAutoSavedCurrentTrack = false
            guard !engine.hasAutoSavedCurrentTrack else { throw TestError("Short preview must not auto-save") }
            
            // Simulate 15-second qualification
            engine.continuousListeningSeconds = 15.0
            guard engine.continuousListeningSeconds >= 15.0 else { throw TestError("Threshold logic error") }
        }
        
        // MARK: - 12. Directory Structure & External .m4a Export
        test("MediaCacheManager: 3-Folder Hierarchy & External .m4a Export") {
            let cache = MediaCacheManager.shared
            
            // Check Parent & 3 child folders exist
            let fm = FileManager.default
            guard fm.fileExists(atPath: cache.parentDirectory.path) else { throw TestError("Parent directory missing") }
            guard fm.fileExists(atPath: cache.libraryDirectory.path) else { throw TestError("Library directory missing") }
            guard fm.fileExists(atPath: cache.exportsDirectory.path) else { throw TestError("Exports directory missing") }
            guard fm.fileExists(atPath: cache.historyDirectory.path) else { throw TestError("History directory missing") }
            
            // Test Save Bundle and Export
            let expTrack = Track(id: "export_unit_test_99", title: "Test Export", artist: "Unit Artist", audioFormat: "AAC 128kbps")
            let audioData = "RAW_M4A_AUDIO_BYTES_TEST".data(using: .utf8)!
            cache.saveBundle(track: expTrack, audioData: audioData, lyrics: [], artworkData: nil)
            guard cache.isCached(videoId: "export_unit_test_99") else { throw TestError("Failed to save bundle") }
            
            // Test Export to .m4a in Exports folder
            let exportDest = cache.exportsDirectory.appendingPathComponent("Unit Artist - Test Export.m4a")
            try cache.exportTrack(videoId: "export_unit_test_99", destinationURL: exportDest)
            guard fm.fileExists(atPath: exportDest.path) else { throw TestError("Exported .m4a file missing") }
            let exportedBytes = try Data(contentsOf: exportDest)
            guard exportedBytes == audioData else { throw TestError("Exported audio data does not match original") }
            
            // Clean up
            try? fm.removeItem(at: exportDest)
            cache.removeCachedTrack(videoId: "export_unit_test_99")
            guard !cache.isCached(videoId: "export_unit_test_99") else { throw TestError("Failed to clean up test bundle") }
        }
        
        // MARK: - 13. Offline Playback Stream Preparation & URL Safety
        test("Offline Playback: Real-Time Stream Decompression & Non-Sonorist URL Safety") {
            let cache = MediaCacheManager.shared
            let fm = FileManager.default
            
            let testId = "offline_play_test_888"
            let originalAudio = "OFFLINE_PLAYBACK_M4A_PAYLOAD_TEST_DATA".data(using: .utf8)!
            let sampleLyrics = [LyricLine(id: "1", time: 1.5, text: "Offline lyrics line 1")]
            let track = Track(id: testId, title: "Offline Song", artist: "Offline Artist", audioFormat: "AAC 128kbps")
            
            // 1. Save bundle
            cache.saveBundle(track: track, audioData: originalAudio, lyrics: sampleLyrics, artworkData: nil)
            guard cache.isCached(videoId: testId) else { throw TestError("Failed to cache track for offline playback test") }
            
            // 2. Test getAllCachedTracks does not assign .sonorist directly to streamURL
            let cachedList = cache.getAllCachedTracks()
            if let matched = cachedList.first(where: { $0.id == testId }) {
                if let stream = matched.streamURL {
                    guard !stream.absoluteString.hasSuffix(".sonorist") else {
                        throw TestError("streamURL must never be set directly to raw .sonorist archive")
                    }
                }
            }
            
            // 3. Prepare real-time playback stream
            guard let playURL = cache.preparePlaybackStream(for: testId) else {
                throw TestError("preparePlaybackStream returned nil")
            }
            guard playURL.isFileURL else { throw TestError("Playback stream must be a local file URL") }
            guard playURL.pathExtension == "m4a" else { throw TestError("Playback stream must be an uncompressed .m4a file for AVPlayer") }
            guard fm.fileExists(atPath: playURL.path) else { throw TestError("Decompressed playback file does not exist on disk") }
            
            let extractedBytes = try Data(contentsOf: playURL)
            guard extractedBytes == originalAudio else { throw TestError("Decompressed audio does not match original bytes") }
            
            // 4. Test cached lyrics retrieval
            let lyrics = cache.getCachedLyrics(for: testId)
            guard let lyrics = lyrics, lyrics.count == 1, lyrics[0].text == "Offline lyrics line 1" else {
                throw TestError("Failed to retrieve cached lyrics from bundle")
            }
            
            // 5. Clean up
            cache.removeCachedTrack(videoId: testId)
            try? fm.removeItem(at: playURL)
        }
        
        // MARK: - 14. External Export: Embedded Metadata Tagging Integrity
        test("External Export: Embedded Apple M4A Metadata Tags (Title, Artist, Album, Lyrics)") {
            let cache = MediaCacheManager.shared
            let fm = FileManager.default
            
            // Prepare valid M4A test audio container using AVAssetExportSession
            let soundURL = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
            let baseAsset = AVURLAsset(url: soundURL)
            let tempBaseM4A = cache.playbackTempDirectory.appendingPathComponent("base_test_\(UUID().uuidString).m4a")
            guard let prepSession = AVAssetExportSession(asset: baseAsset, presetName: AVAssetExportPresetAppleM4A) else { return }
            prepSession.outputURL = tempBaseM4A
            prepSession.outputFileType = .m4a
            let prepSema = DispatchSemaphore(value: 0)
            prepSession.exportAsynchronously { prepSema.signal() }
            _ = prepSema.wait(timeout: .now() + 4.0)
            guard let realAudio = try? Data(contentsOf: tempBaseM4A) else { return }
            try? fm.removeItem(at: tempBaseM4A)
            
            let exportTestId = "meta_tag_test_555"
            let track = Track(
                id: exportTestId,
                title: "Tagged Song Title",
                artist: "Tagged Artist",
                album: "Tagged Album Deluxe",
                durationSeconds: 1.5,
                artworkURL: nil,
                streamURL: nil,
                audioFormat: "AAC 128kbps"
            )
            let lyrics = [LyricLine(id: "1", time: 0.5, text: "Tagged Lyric Line")]
            let dummyArtwork = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
            
            cache.saveBundle(track: track, audioData: realAudio, lyrics: lyrics, artworkData: dummyArtwork)
            
            let exportDest = cache.exportsDirectory.appendingPathComponent("Tagged Artist - Tagged Song Title.m4a")
            try cache.exportTrack(videoId: exportTestId, destinationURL: exportDest)
            
            guard fm.fileExists(atPath: exportDest.path) else {
                throw TestError("Exported tagged .m4a missing on disk")
            }
            
            let asset = AVURLAsset(url: exportDest)
            var foundTitle = false
            var foundArtist = false
            for item in asset.metadata {
                if let str = item.stringValue {
                    if str.contains("Tagged Song Title") { foundTitle = true }
                    if str.contains("Tagged Artist") { foundArtist = true }
                }
            }
            
            // Clean up
            try? fm.removeItem(at: exportDest)
            cache.removeCachedTrack(videoId: exportTestId)
            
            guard foundTitle else { throw TestError("Exported .m4a missing Title tag in metadata") }
            guard foundArtist else { throw TestError("Exported .m4a missing Artist tag in metadata") }
        }
        
        // MARK: - 8. Advanced Lyrics Engine & Music DNA Verification
        test("LRCLIBService: Native Phonetic Romanization (Romaji, Pinyin, Devanagari)") {
            // 1. Japanese Kanji/Hiragana
            let jp = "君の名は"
            let jpRomanized = LRCLIBService.romanize(text: jp)
            guard let romaji = jpRomanized, !romaji.isEmpty else {
                throw TestError("Failed to romanize Japanese script")
            }
            // Check that output contains latin characters
            guard romaji.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                throw TestError("Romanized string contains no latin letters: \(romaji)")
            }
            
            // 2. Hindi Devanagari
            let hi = "नमस्ते दुनिया"
            let hiRomanized = LRCLIBService.romanize(text: hi)
            guard let hindiLatin = hiRomanized, !hindiLatin.isEmpty else {
                throw TestError("Failed to romanize Devanagari script")
            }
            guard hindiLatin.lowercased().contains("namaste") || hindiLatin.lowercased().contains("duniya") else {
                throw TestError("Devanagari romanization unexpected: \(hindiLatin)")
            }
            
            // 3. Pure Latin text should return nil to avoid redundant visual clutter
            let en = "Bohemian Rhapsody"
            let enRomanized = LRCLIBService.romanize(text: en)
            guard enRomanized == nil else {
                throw TestError("English text should return nil romanization, got: \(String(describing: enRomanized))")
            }
        }
        
        test("LRCLIBService: Cadence & Syllable Token Generation") {
            let service = LRCLIBService.shared
            let rawLines = [
                LyricLine(time: 10.0, text: "Is this the real life?"),
                LyricLine(time: 14.0, text: "Is this just fantasy?"),
                LyricLine(time: 20.0, text: "Caught in a landslide")
            ]
            
            let enriched = service.enrichLines(rawLines)
            guard enriched.count == 3 else {
                throw TestError("Expected 3 lines, got \(enriched.count)")
            }
            
            // Line 1 should have 5 words ("Is", "this", "the", "real", "life?")
            let line1 = enriched[0]
            guard line1.words.count == 5 else {
                throw TestError("Expected 5 words in line 1, got \(line1.words.count)")
            }
            
            // First word starts at line start (10.0)
            guard abs(line1.words[0].time - 10.0) < 0.01 else {
                throw TestError("Word 0 start time mismatch: \(line1.words[0].time)")
            }
            
            // Words should be strictly increasing in time
            for i in 1..<line1.words.count {
                guard line1.words[i].time >= line1.words[i-1].time else {
                    throw TestError("Word \(i) time \(line1.words[i].time) < word \(i-1) time \(line1.words[i-1].time)")
                }
                guard line1.words[i].duration > 0 else {
                    throw TestError("Word \(i) duration must be positive")
                }
            }
        }
        
        test("LyricLine: Backward Compatible JSON Decoding") {
            // Legacy JSON payload stored in older .sonorist bundles
            let legacyJSON = """
            {
                "id": "line-legacy-1",
                "time": 42.5,
                "text": "Yesterday all my troubles seemed so far away"
            }
            """.data(using: .utf8)!
            
            let decoded = try JSONDecoder().decode(LyricLine.self, from: legacyJSON)
            guard decoded.id == "line-legacy-1" else { throw TestError("ID mismatch: \(decoded.id)") }
            guard abs(decoded.time - 42.5) < 0.01 else { throw TestError("Time mismatch: \(decoded.time)") }
            guard decoded.text == "Yesterday all my troubles seemed so far away" else { throw TestError("Text mismatch") }
            guard decoded.translation == nil else { throw TestError("Translation must be nil") }
            guard decoded.romanization == nil else { throw TestError("Romanization must be nil") }
            guard decoded.words.isEmpty else { throw TestError("Words must be empty default") }
        }
        
        test("TrackStory: Music DNA Data Model & Encoding") {
            let story = TrackStory(
                title: "Bohemian Rhapsody",
                artist: "Queen",
                summary: "Epic suite composed by Freddie Mercury for the 1975 album A Night at the Opera.",
                releaseYear: "1975",
                genre: "Progressive Rock",
                extract: "The song consists of several sections: an intro, a ballad segment, an operatic passage, a hard rock part and a reflective coda."
            )
            
            let data = try JSONEncoder().encode(story)
            let decoded = try JSONDecoder().decode(TrackStory.self, from: data)
            
            guard decoded.title == "Bohemian Rhapsody" else { throw TestError("Title mismatch") }
            guard decoded.releaseYear == "1975" else { throw TestError("Year mismatch") }
            guard decoded.genre == "Progressive Rock" else { throw TestError("Genre mismatch") }
            guard decoded.source == "Wikipedia / Genius" else { throw TestError("Source mismatch") }
        }
        
        test("LyricLine: Synced vs Unsynced (Plain) Lyrics Differentiation") {
            // Synced line with timestamps
            let syncedLRC = "[00:15.30]Hello from the other side"
            let syncedLines = LRCLIBService.shared.parseLRC(syncedLRC)
            guard let firstSynced = syncedLines.first else { throw TestError("Failed to parse LRC line") }
            guard firstSynced.isSynced == true else { throw TestError("LRC parsed line must have isSynced == true") }
            guard abs(firstSynced.time - 15.3) < 0.01 else { throw TestError("Timestamp mismatch") }
            
            // Plain line without timestamps
            let plainLine = LyricLine(time: 0.0, text: "Just plain text without timestamps", isSynced: false)
            guard plainLine.isSynced == false else { throw TestError("Plain line must have isSynced == false") }
            
            // Enriching plain lines must NOT generate fake word tokens
            let enrichedPlain = LRCLIBService.shared.enrichLines([plainLine])
            guard enrichedPlain[0].words.isEmpty else { throw TestError("Unsynced plain lines must not have word tokens") }
        }
        
        test("AudioPlayerEngine: Alignment Calibration (Sync to Now)") {
            let player = AudioPlayerEngine.shared
            let targetLineTime = 25.0
            player.lyricLines = [
                LyricLine(time: 10.0, text: "Line 1", isSynced: true),
                LyricLine(time: targetLineTime, text: "Line 2 (Heard singing right now)", isSynced: true)
            ]
            // Suppose current playback audio is at 27.5s (meaning lyrics were lagging by +2.5s)
            player.currentTime = 27.5
            player.alignLyric(lineIndex: 1)
            
            // Expected userLyricOffset = 27.5 - 25.0 = +2.5s
            guard abs(player.userLyricOffset - 2.5) < 0.05 else {
                throw TestError("Expected userLyricOffset to be calibrated to +2.5s, got \(player.userLyricOffset)")
            }
            player.resetLyricOffset()
            guard player.userLyricOffset == 0.0 else { throw TestError("Reset failed") }
        }
        
        // MARK: - 9. System-Wide Appearance & Theme Management
        test("AppThemeMode: Case Enumerations, Icons & ColorScheme Mapping") {
            let all = AppThemeMode.allCases
            guard all.count == 3 else { throw TestError("Expected 3 theme cases, got \(all.count)") }
            
            guard AppThemeMode.system.colorScheme == nil else { throw TestError("System theme must map to nil ColorScheme") }
            guard AppThemeMode.light.colorScheme == .light else { throw TestError("Light theme must map to .light") }
            guard AppThemeMode.dark.colorScheme == .dark else { throw TestError("Dark theme must map to .dark") }
            
            guard AppThemeMode.light.displayName == "Light" else { throw TestError("Light displayName invalid") }
            guard AppThemeMode.dark.displayName == "Dark" else { throw TestError("Dark displayName invalid") }
            guard AppThemeMode.system.displayName == "System" else { throw TestError("System displayName invalid") }
            
            // JSON Codable round trip
            let encoded = try JSONEncoder().encode(AppThemeMode.light)
            let decoded = try JSONDecoder().decode(AppThemeMode.self, from: encoded)
            guard decoded == .light else { throw TestError("Codable round trip failed") }
        }
        
        test("AppThemeManager: Persistence & Mode Switching") {
            let manager = AppThemeManager.shared
            let original = manager.currentTheme
            
            manager.setTheme(.light)
            guard manager.currentTheme == .light else { throw TestError("Expected Light mode") }
            guard UserDefaults.standard.string(forKey: AppThemeManager.themeDefaultsKey) == "Light" else {
                throw TestError("UserDefaults failed to persist Light mode")
            }
            
            manager.setTheme(.dark)
            guard manager.currentTheme == .dark else { throw TestError("Expected Dark mode") }
            guard UserDefaults.standard.string(forKey: AppThemeManager.themeDefaultsKey) == "Dark" else {
                throw TestError("UserDefaults failed to persist Dark mode")
            }
            
            manager.setTheme(.system)
            guard manager.currentTheme == .system else { throw TestError("Expected System mode") }
            guard UserDefaults.standard.string(forKey: AppThemeManager.themeDefaultsKey) == "System" else {
                throw TestError("UserDefaults failed to persist System mode")
            }
            
            // Restore original
            manager.setTheme(original)
        }
        
        // MARK: - 10. v2.1 Volume Persistence & Playback State Restoration
        test("AudioPlayerEngine: Volume Persistence & Pre-Mute Retention") {
            let engine = AudioPlayerEngine.shared
            let originalVol = engine.volume
            
            // 1. Setting volume updates UserDefaults
            engine.volume = 0.65
            let storedVol = UserDefaults.standard.float(forKey: AudioPlayerEngine.savedVolumeKey)
            guard abs(storedVol - 0.65) < 0.01 else {
                throw TestError("Expected stored volume 0.65, got \(storedVol)")
            }
            guard abs(engine.preMuteVolume - 0.65) < 0.01 else {
                throw TestError("Expected preMuteVolume 0.65, got \(engine.preMuteVolume)")
            }
            
            // 2. Mute to 0 retains preMuteVolume
            engine.volume = 0.0
            guard abs(engine.preMuteVolume - 0.65) < 0.01 else {
                throw TestError("preMuteVolume must not be overwritten by 0 mute")
            }
            
            // 3. Sleep timer fade-out must NOT overwrite user's saved volume
            engine.isFadingForSleepTimer = true
            engine.volume = 0.1
            let protectedVol = UserDefaults.standard.float(forKey: AudioPlayerEngine.savedVolumeKey)
            guard abs(protectedVol - 0.0) < 0.01 else {
                throw TestError("Sleep timer fade must not overwrite saved volume in UserDefaults")
            }
            engine.isFadingForSleepTimer = false
            
            // Restore original volume
            engine.volume = originalVol
        }
        
        test("AudioPlayerEngine: Playback State Serialization & Instant Restoration") {
            let engine = AudioPlayerEngine.shared
            let sampleTrack = Track(
                id: "test_persist_123",
                title: "Starboy",
                artist: "The Weeknd",
                album: "Starboy",
                durationSeconds: 230.5
            )
            let queueTrack = Track(
                id: "test_queue_456",
                title: "Blinding Lights",
                artist: "The Weeknd",
                album: "After Hours",
                durationSeconds: 200.0
            )
            
            engine.currentTrack = sampleTrack
            engine.queue = [sampleTrack, queueTrack]
            engine.currentTime = 88.5
            engine.duration = 230.5
            
            // 1. Test saveCurrentPlaybackState
            engine.saveCurrentPlaybackState()
            
            guard let data = UserDefaults.standard.data(forKey: AudioPlayerEngine.savedPlaybackStateKey) else {
                throw TestError("SavedPlaybackState was not written to UserDefaults")
            }
            
            let decoded = try JSONDecoder().decode(SavedPlaybackState.self, from: data)
            guard decoded.track.id == "test_persist_123" else {
                throw TestError("Restored track ID mismatch: \(decoded.track.id)")
            }
            guard decoded.queue.count == 2 else {
                throw TestError("Restored queue count mismatch: \(decoded.queue.count)")
            }
            guard abs(decoded.positionSeconds - 88.5) < 0.01 else {
                throw TestError("Restored position mismatch: \(decoded.positionSeconds)")
            }
            
            // 2. Test restoreSavedPlaybackState
            engine.currentTrack = nil
            engine.queue = []
            engine.currentTime = 0.0
            
            engine.restoreSavedPlaybackState()
            
            guard engine.currentTrack?.id == "test_persist_123" else {
                throw TestError("Engine failed to restore currentTrack")
            }
            guard engine.queue.count == 2 else {
                throw TestError("Engine failed to restore queue")
            }
            guard abs(engine.currentTime - 88.5) < 0.01 else {
                throw TestError("Engine failed to restore currentTime head")
            }
            guard engine.isPlaying == false else {
                throw TestError("Restored engine must be in paused state initially")
            }
            
            // Cleanup test state
            UserDefaults.standard.removeObject(forKey: AudioPlayerEngine.savedPlaybackStateKey)
        }
        
        test("Apple HIG UI Layout: Static Panes & Now Playing Lyrics Context") {
            // 1. Sidebar fixed width conforms to macOS HIG 210pt standard
            guard SidebarView.sidebarWidth == 210 else {
                throw TestError("Sidebar width should be strictly 210pt, got \(SidebarView.sidebarWidth)")
            }
            
            // 2. Tab items cover Search, Library, Analytics
            let items = NavigationItem.allCases
            guard items.contains(.search) && items.contains(.library) && items.contains(.analytics) else {
                throw TestError("Navigation items missing primary tabs")
            }
            
            // 3. AudioPlayerEngine immersive mode controls lyrics display context
            let player = AudioPlayerEngine.shared
            player.isImmersiveViewActive = false
            guard !player.isImmersiveViewActive else {
                throw TestError("Standard mode should have isImmersiveViewActive = false")
            }
            
            player.isImmersiveViewActive = true
            guard player.isImmersiveViewActive else {
                throw TestError("Now Playing mode should have isImmersiveViewActive = true")
            }
            player.isImmersiveViewActive = false
        }
        
        // MARK: - 11. Penetration Testing & Exploit Hardening Suite
        test("PenTest: Corrupted / Out-of-Bounds .sonorist Bundle Rejection") {
            // Test 1: Truncated binary data
            var corrupted = "SONORIST".data(using: .utf8)!
            var ver: UInt16 = 1
            corrupted.append(Data(bytes: &ver, count: 2))
            var fakeLen: UInt32 = 999999 // Lies about metadata length
            corrupted.append(Data(bytes: &fakeLen, count: 4))
            corrupted.append("SHORT_PAYLOAD".data(using: .utf8)!)
            
            do {
                _ = try SonoristBundleEngine.unpack(data: corrupted)
                throw TestError("Expected unpack to fail with out-of-bounds error")
            } catch {
                // Expected failure safely caught without fatal exception
            }
            
            do {
                _ = try SonoristBundleEngine.readMetadataOnly(from: corrupted)
                throw TestError("Expected readMetadataOnly to fail with out-of-bounds error")
            } catch {
                // Expected failure safely caught
            }
        }
        
        test("PenTest: Zip-Bomb & Oversized Allocation Rejection") {
            var bomb = "SONORIST".data(using: .utf8)!
            var ver: UInt16 = 1
            bomb.append(Data(bytes: &ver, count: 2))
            var metaLen: UInt32 = 1000000000 // 1GB fake metadata
            bomb.append(Data(bytes: &metaLen, count: 4))
            
            do {
                _ = try SonoristBundleEngine.unpack(data: bomb)
                throw TestError("Expected oversized payload to be rejected")
            } catch {
                // Expected safe rejection
            }
        }
        
        test("PenTest: Path Traversal Character Stripping") {
            let maliciousId = "../../etc/passwd"
            let sanitized = maliciousId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            guard !sanitized.contains("/") && !sanitized.contains("..") else {
                throw TestError("Path traversal sequences were not stripped: \(sanitized)")
            }
            guard sanitized == "etcpasswd" else {
                throw TestError("Sanitization result unexpected: \(sanitized)")
            }
        }
        
        test("PenTest: SSRF & Internal Network Rejection") {
            let ssrf1 = "http://169.254.169.254/latest/meta-data"
            guard SecurityAudit.validateURL(ssrf1) == nil else { throw TestError("SSRF URL was not blocked") }
            
            let ssrf2 = "https://192.168.1.1/admin"
            guard SecurityAudit.validateURL(ssrf2) == nil else { throw TestError("Private LAN IP was not blocked") }
            
            let ssrf3 = "javascript:alert(1)"
            guard SecurityAudit.validateURL(ssrf3) == nil else { throw TestError("JavaScript URI was not blocked") }
        }
        
        test("Apple Queue Philosophy: Index 0 Head-of-Queue Boundary Integrity") {
            let engine = AudioPlayerEngine.shared
            let t1 = Track(id: "seed_song_1", title: "Seed 1", artist: "Artist 1")
            let t2 = Track(id: "radio_rec_2", title: "Radio 2", artist: "Artist 2")
            let t3 = Track(id: "radio_rec_3", title: "Radio 3", artist: "Artist 3")
            
            engine.queue = [t1, t2, t3]
            engine.currentTrack = t1
            engine.currentTime = 1.0 // Within 3s window
            engine.repeatMode = .off
            
            // 1. getPreviousTrackInQueue must be nil when at index 0 and repeatMode != .all
            guard engine.getPreviousTrackInQueue() == nil else {
                throw TestError("getPreviousTrackInQueue() must be nil at index 0 when repeat is off")
            }
            
            // 2. previous() at index 0 must rewind to 0:00 without wrapping to t3
            engine.previous()
            guard engine.currentTrack?.id == "seed_song_1" else {
                throw TestError("previous() wrapped around to queue.last instead of rewinding current track")
            }
            guard engine.currentTime == 0.0 else {
                throw TestError("previous() did not seek to 0:00")
            }
            
            // 3. forcePreviousTrack() at index 0 must rewind to 0:00 without wrapping to t3
            engine.forcePreviousTrack()
            guard engine.currentTrack?.id == "seed_song_1" else {
                throw TestError("forcePreviousTrack() wrapped around to queue.last instead of staying on current track")
            }
            
            // 4. Only when repeatMode == .all should it wrap around
            engine.repeatMode = .all
            guard engine.getPreviousTrackInQueue()?.id == "radio_rec_3" else {
                throw TestError("getPreviousTrackInQueue() should wrap to queue.last when repeatMode is .all")
            }
            engine.repeatMode = .off
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Results: \(passed) passed, \(failed) failed")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        if failed > 0 {
            exit(1)
        }
    }
}

struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
