import Foundation
import AVFoundation
import MediaPlayer
import Combine
import AppKit

public enum SleepTimerOption: String, CaseIterable, Identifiable {
    case off = "Off"
    case min15 = "15 minutes"
    case min30 = "30 minutes"
    case min45 = "45 minutes"
    case min60 = "1 hour"
    case endOfTrack = "End of track"
    
    public var id: String { rawValue }
    
    public var durationSeconds: Int? {
        switch self {
        case .off: return nil
        case .min15: return 15 * 60
        case .min30: return 30 * 60
        case .min45: return 45 * 60
        case .min60: return 60 * 60
        case .endOfTrack: return nil
        }
    }
}

/// Persistent snapshot of playback state restored across app launches
public struct SavedPlaybackState: Codable, Sendable {
    public let track: Track
    public let queue: [Track]
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let savedAt: Date
    
    public init(track: Track, queue: [Track], positionSeconds: Double, durationSeconds: Double = 0, savedAt: Date = Date()) {
        self.track = track
        self.queue = queue
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.savedAt = savedAt
    }
}

/// Dedicated observable tracker for high-frequency playback position updates.
/// Decoupling this from AudioPlayerEngine prevents full view-tree invalidation
/// of MainContentView, SidebarView, SearchView, LibraryView, and TrackRowViews on every audio clock tick.
@MainActor
public final class PlaybackProgressTracker: ObservableObject {
    public static let shared = PlaybackProgressTracker()
    
    @Published public var currentTime: Double = 0
    
    public init() {}
}

/// Comprehensive audio playback engine powered by AVFoundation
/// Features Queue management, offline caching, lyrics, favorites, and system Now Playing integration.
@MainActor
public final class AudioPlayerEngine: ObservableObject {
    public static let shared = AudioPlayerEngine()
    
    public static let savedVolumeKey = "sonorist_saved_volume"
    public static let savedPlaybackStateKey = "sonorist_saved_playback_state"
    
    // Playback state
    @Published public var currentTrack: Track?
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    public var currentTime: Double {
        get { PlaybackProgressTracker.shared.currentTime }
        set { PlaybackProgressTracker.shared.currentTime = newValue }
    }
    @Published public var duration: Double = 0
    
    // Volume state & pre-mute retention
    public var preMuteVolume: Float = 0.8
    public var isFadingForSleepTimer: Bool = false
    private var lastSavedPosition: Double = 0.0
    
    @Published public var volume: Float = 0.8 {
        didSet {
            player?.volume = volume
            if !isFadingForSleepTimer {
                if volume > 0 {
                    preMuteVolume = volume
                }
                UserDefaults.standard.set(volume, forKey: Self.savedVolumeKey)
            }
        }
    }
    @Published public var queue: [Track] = []
    @Published public var isShuffle: Bool = false
    @Published public var isRepeat: Bool = false
    @Published public var isAutoplayEnabled: Bool = true
    @Published public var errorMessage: String?
    
    public static let savedImmersiveKey = "SonoristIsImmersiveActive"
    
    // UI View Modes (Apple Music Immersive & MiniPlayer)
    @Published public var isImmersiveViewActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isImmersiveViewActive, forKey: Self.savedImmersiveKey)
        }
    }
    @Published public var isMiniPlayerActive: Bool = false
    
    // Synced Lyrics (LRCLIB Integration)
    @Published public var lyricLines: [LyricLine] = []
    @Published public var activeLyricIndex: Int = 0
    @Published public var isLoadingLyrics: Bool = false
    @Published public var isLyricsSynced: Bool = true
    @Published public var lyricLeadTime: Double = 0.35 // 350ms lead time compensation (Apple Music / Karaoke standard)
    @Published public var userLyricOffset: Double = 0.0 // User fine-tuning per-track in seconds (-5.0s to +5.0s)
    @Published public var showSyncCalibrationPopover: Bool = false
    
    // Advanced Lyrics & Music DNA features (Echo-Music / Apple Music standard)
    @Published public var showTranslation: Bool = false
    @Published public var showRomanization: Bool = false
    @Published public var showTrackStory: Bool = false
    @Published public var trackStory: TrackStory? = nil
    @Published public var isLoadingStory: Bool = false
    @Published public var isTranslatingLyrics: Bool = false
    @Published public var activeWordIndex: Int = -1
    @Published public var targetTranslationLanguage: String = "en"
    
    // Sleep Timer
    @Published public var sleepTimerOption: SleepTimerOption = .off
    @Published public var sleepTimerRemainingSeconds: Int = 0
    private var sleepTimerTask: Task<Void, Never>?
    private var preFadeVolume: Float = 0.8
    
    // Scrubber UI state
    @Published public var isDraggingScrubber: Bool = false
    @Published public var dragScrubTime: Double = 0
    
    // Extra Options & User Features
    @Published public var likedTracks: [Track] = []
    @Published public var playHistory: [Track] = []
    @Published public var downloadingTrackIDs: Set<String> = []
    
    // Audio Stream Quality Selection
    @Published public var selectedAudioQuality: AudioQuality = .standard
    @Published public var availableStreamOptions: [AudioStreamOption] = []
    
    // Audio Settings & Equalizer
    @Published public var equalizerPreset: String = "Flat"
    @Published public var isEqualizerEnabled: Bool = true
    @Published public var equalizerPreamp: Double = 0.0 // -12dB to +12dB
    @Published public var equalizerBands: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    
    @Published public var audioQualitySetting: String = "AAC 128kbps (Lossless Container)"
    @Published public var isAudioNormalized: Bool = true
    @Published public var crossfadeDuration: Double = 3.0
    
    // Panels & Modals
    @Published public var showQueueSheet: Bool = false
    @Published public var showLyricsSheet: Bool = false
    @Published public var showEqualizerSheet: Bool = false
    @Published public var showSettingsSheet: Bool = false
    
    public static let equalizerPresets: [String: [Double]] = [
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Acoustic": [4.5, 4.0, 2.5, 1.0, 1.5, 1.5, 3.0, 3.5, 3.0, 2.0],
        "Bass Booster": [6.0, 5.5, 4.0, 2.5, 1.0, 0, 0, 0, 0, 0],
        "Bass Reducer": [-6.0, -5.5, -4.0, -2.5, -1.0, 0, 0, 0, 0, 0],
        "Classical": [4.5, 3.5, 3.0, 2.5, -1.5, -1.5, 0, 2.0, 3.5, 3.5],
        "Electronic": [5.0, 4.0, 1.5, 0, -2.0, 2.0, 1.0, 2.0, 4.5, 5.0],
        "Hip-Hop": [5.5, 4.5, 1.5, 2.5, -1.0, -1.0, 1.5, -1.0, 2.0, 3.0],
        "Jazz": [3.5, 2.5, 1.0, 1.5, -1.5, -1.5, 0, 1.5, 3.0, 3.5],
        "Pop": [-1.5, -1.0, 0.5, 2.5, 4.0, 3.5, 1.5, -1.0, -1.5, -1.5],
        "Rock": [5.0, 3.5, -1.5, -3.0, -1.0, 1.0, 3.5, 4.5, 4.5, 4.5],
        "Vocal Booster": [-1.0, -1.0, 0, 2.0, 4.0, 4.5, 3.5, 2.0, 0.5, -1.0]
    ]
    
    public func applyPreset(_ name: String) {
        self.equalizerPreset = name
        if let values = Self.equalizerPresets[name] {
            self.equalizerBands = values
        }
    }
    
    public func setBand(index: Int, value: Double) {
        guard index >= 0 && index < equalizerBands.count else { return }
        equalizerBands[index] = max(-12.0, min(12.0, value))
        equalizerPreset = "Custom"
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private let cacheManager = MediaCacheManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Intentional Listening Gate State
    public var continuousListeningSeconds: Double = 0.0
    public var hasAutoSavedCurrentTrack: Bool = false
    private var currentStreamRemoteURL: URL? = nil
    private var autoSaveTask: Task<Void, Never>? = nil
    
    public init() {
        // 1. Restore persistent volume level across app launches
        if UserDefaults.standard.object(forKey: Self.savedVolumeKey) != nil {
            let savedVol = UserDefaults.standard.float(forKey: Self.savedVolumeKey)
            self.volume = savedVol
            if savedVol > 0 {
                self.preMuteVolume = savedVol
            }
        }
        
        setupRemoteCommands()
        loadLikedTracks()
        restoreSavedPlaybackState()
        setupAppLifecycleObservers()
    }
    
    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
    }
    
    // MARK: - App Lifecycle Observers & State Persistence
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveCurrentPlaybackState()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveCurrentPlaybackState()
            }
            .store(in: &cancellables)
    }
    
    /// Persists current track, position head, and queue to disk
    public func saveCurrentPlaybackState() {
        guard let track = currentTrack else { return }
        let state = SavedPlaybackState(
            track: track,
            queue: queue,
            positionSeconds: currentTime,
            durationSeconds: duration > 0 ? duration : track.durationSeconds
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.savedPlaybackStateKey)
        }
    }
    
    /// Restores last played track, queue, and playback head timestamp
    public func restoreSavedPlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedPlaybackStateKey),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data),
              !state.track.id.isEmpty else {
            return
        }
        
        self.currentTrack = state.track
        self.queue = state.queue
        self.currentTime = state.positionSeconds
        self.lastSavedPosition = state.positionSeconds
        self.duration = state.durationSeconds > 0 ? state.durationSeconds : state.track.durationSeconds
        self.isPlaying = false
        self.isBuffering = false
        
        // Update macOS Now Playing info with restored state
        self.updateNowPlaying(track: state.track)
        self.updateNowPlayingPlaybackTime()
        
        // Restore Immersive Now Playing mode if user was in Now Playing view
        if UserDefaults.standard.object(forKey: Self.savedImmersiveKey) != nil {
            self.isImmersiveViewActive = UserDefaults.standard.bool(forKey: Self.savedImmersiveKey)
        }
        
        // Pre-fetch lyrics in background
        Task { [weak self] in
            guard let self = self else { return }
            await self.loadLyrics(for: state.track)
        }
        
        // Prepare AVPlayer in paused state at restored position
        self.prepareRestoredTrack(track: state.track, seekTo: state.positionSeconds)
    }
    
    private func prepareRestoredTrack(track: Track, seekTo: Double) {
        Task {
            do {
                let streamURL: URL
                let formatBadge: String
                
                if track.id.hasPrefix("local_"), let localURL = track.streamURL, localURL.isFileURL {
                    streamURL = localURL
                    formatBadge = track.audioFormat
                } else if let playbackURL = cacheManager.preparePlaybackStream(for: track.id) {
                    streamURL = playbackURL
                    formatBadge = "Offline (.sonorist)"
                    self.availableStreamOptions = [
                        AudioStreamOption(quality: .standard, itag: 140, mimeType: "audio/mp4", bitrate: 128000, label: "Sonorist Compressed")
                    ]
                } else {
                    let (resolvedURL, badge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: self.selectedAudioQuality)
                    streamURL = resolvedURL
                    formatBadge = badge
                    self.availableStreamOptions = options
                    self.currentStreamRemoteURL = resolvedURL
                }
                
                var updatedTrack = track
                updatedTrack.streamURL = streamURL
                updatedTrack.audioFormat = formatBadge
                updatedTrack.isCached = cacheManager.isCached(videoId: track.id)
                updatedTrack.isLiked = isLiked(track: track)
                self.currentTrack = updatedTrack
                
                self.startPlayer(with: streamURL, track: updatedTrack, autoPlay: false, seekTo: seekTo)
            } catch {
                #if DEBUG
                print("[Restore Track Error]: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Playback Controls
    
    /// Loads and plays a track, resolving stream URLs dynamically
    public func play(track: Track, autoPlay: Bool = true, seekTo: Double? = nil) {
        self.currentTrack = track
        self.isBuffering = true
        self.errorMessage = nil
        if let seek = seekTo {
            self.currentTime = seek
            self.lastSavedPosition = seek
        } else {
            self.currentTime = 0
            self.lastSavedPosition = 0
        }
        
        // Reset Intentional Listening Filter
        self.continuousListeningSeconds = 0.0
        self.hasAutoSavedCurrentTrack = cacheManager.isCached(videoId: track.id)
        self.currentStreamRemoteURL = nil
        self.autoSaveTask?.cancel()
        
        // Add to history
        if !playHistory.contains(where: { $0.id == track.id }) {
            playHistory.insert(track, at: 0)
        }
        
        // Record into Listening Analytics
        let isCached = MediaCacheManager.shared.isCached(videoId: track.id)
        ListeningAnalyticsManager.shared.recordTrackStart(track: track, quality: selectedAudioQuality, isCached: isCached)
        
        Task {
            do {
                let streamURL: URL
                let formatBadge: String
                
                // 1. Check local audio file imported from user disk (prefixed with local_)
                if track.id.hasPrefix("local_"), let localURL = track.streamURL, localURL.isFileURL {
                    streamURL = localURL
                    formatBadge = track.audioFormat
                    self.hasAutoSavedCurrentTrack = true
                }
                // 2. Check compressed .sonorist library
                else if let playbackURL = cacheManager.preparePlaybackStream(for: track.id) {
                    streamURL = playbackURL
                    formatBadge = "Offline (.sonorist)"
                    self.hasAutoSavedCurrentTrack = true
                    self.availableStreamOptions = [
                        AudioStreamOption(quality: .standard, itag: 140, mimeType: "audio/mp4", bitrate: 128000, label: "Sonorist Compressed")
                    ]
                } else {
                    // 3. Resolve stream via InnerTube with user-selected quality
                    let (resolvedURL, badge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: self.selectedAudioQuality)
                    streamURL = resolvedURL
                    formatBadge = badge
                    self.availableStreamOptions = options
                    self.currentStreamRemoteURL = resolvedURL
                }
                
                var updatedTrack = track
                updatedTrack.streamURL = streamURL
                updatedTrack.audioFormat = formatBadge
                updatedTrack.isCached = cacheManager.isCached(videoId: track.id)
                updatedTrack.isLiked = isLiked(track: track)
                self.currentTrack = updatedTrack
                
                self.startPlayer(with: streamURL, track: updatedTrack, autoPlay: autoPlay, seekTo: seekTo)
                
                // Fetch synced lyrics in background
                await self.loadLyrics(for: updatedTrack)
                
                self.saveCurrentPlaybackState()
            } catch {
                self.isBuffering = false
                self.errorMessage = "Playback error: \(error.localizedDescription)"
                #if DEBUG
                print("[Player Error]: \(error)")
                #endif
            }
        }
    }
    
    /// Switches the audio stream quality seamlessly during active playback
    public func switchQuality(to quality: AudioQuality) {
        FluidHaptics.tap()
        guard let track = currentTrack, !track.id.hasPrefix("local_") else { return }
        self.selectedAudioQuality = quality
        let savedTime = self.currentTime
        let wasPlaying = self.isPlaying
        
        Task {
            do {
                let (streamURL, formatBadge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: quality)
                var updated = track
                updated.streamURL = streamURL
                updated.audioFormat = formatBadge
                self.currentTrack = updated
                self.availableStreamOptions = options
                
                self.startPlayer(with: streamURL, track: updated, autoPlay: wasPlaying, seekTo: savedTime)
            } catch {
                #if DEBUG
                print("[Quality switch error]: \(error)")
                #endif
            }
        }
    }
    
    private func startPlayer(with url: URL, track: Track, autoPlay: Bool = true, seekTo: Double? = nil) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(
                url: url,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"
                    ]
                ]
            )
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.volume = volume
        self.player = newPlayer
        
        // Observe status & buffering
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.duration = playerItem.duration.seconds.isFinite ? playerItem.duration.seconds : track.durationSeconds
                    if let targetSeek = seekTo, targetSeek > 0 {
                        let targetTime = CMTime(seconds: targetSeek, preferredTimescale: 600)
                        self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = targetSeek
                    }
                    self.updateNowPlaying(track: track)
                    if autoPlay {
                        self.player?.play()
                        self.isPlaying = true
                    } else {
                        self.isPlaying = false
                    }
                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false
                    let desc = playerItem.error?.localizedDescription ?? "Stream failed to load."
                    
                    // Self-healing fallback: If offline file failed to open, try falling back to online stream
                    if url.isFileURL && !track.id.hasPrefix("local_") {
                        #if DEBUG
                        print("[Player Engine]: Offline file playback failed (\(desc)). Falling back to live stream...")
                        #endif
                        Task { @MainActor in
                            do {
                                let (resolvedURL, badge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: self.selectedAudioQuality)
                                var updated = track
                                updated.streamURL = resolvedURL
                                updated.audioFormat = badge
                                self.currentTrack = updated
                                self.availableStreamOptions = options
                                self.currentStreamRemoteURL = resolvedURL
                                self.startPlayer(with: resolvedURL, track: updated, autoPlay: autoPlay, seekTo: seekTo)
                            } catch {
                                self.errorMessage = "Playback error: \(desc)"
                            }
                        }
                    } else {
                        self.errorMessage = "Playback error: \(desc)"
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Periodic time observer for smooth UI scrubbing & lyric line synchronization (250ms interval reduces timer wakeups by 40%)
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.isDraggingScrubber {
                    self.currentTime = time.seconds
                    if self.isPlaying {
                        ListeningAnalyticsManager.shared.recordListeningTime(seconds: 0.25, track: self.currentTrack)
                        
                        // Intentional Listening 15-second skip filter:
                        if !self.hasAutoSavedCurrentTrack && self.currentTrack != nil {
                            self.continuousListeningSeconds += 0.25
                            if self.continuousListeningSeconds >= 15.0 {
                                self.triggerAutoSaveForCurrentTrack()
                            }
                        }
                        
                        // Throttled periodic save of playback position every ~2 seconds
                        if abs(self.currentTime - self.lastSavedPosition) >= 2.0 {
                            self.lastSavedPosition = self.currentTime
                            self.saveCurrentPlaybackState()
                        }
                    }
                }
                
                // Real-time synced lyric line detection with natural lead time & user offset (Only if truly synced)
                if self.isLyricsSynced && !self.lyricLines.isEmpty {
                    let syncTime = self.currentTime + self.lyricLeadTime + self.userLyricOffset
                    var best = 0
                    for (idx, line) in self.lyricLines.enumerated() {
                        if line.time <= syncTime {
                            best = idx
                        } else {
                            break
                        }
                    }
                    if self.activeLyricIndex != best {
                        self.activeLyricIndex = best
                    }
                    
                    // Word-by-word / syllable karaoke cadence synchronization
                    if best < self.lyricLines.count {
                        let currentLine = self.lyricLines[best]
                        var currentWord = -1
                        for (wIdx, word) in currentLine.words.enumerated() {
                            if word.time <= syncTime {
                                currentWord = wIdx
                            } else {
                                break
                            }
                        }
                        if self.activeWordIndex != currentWord {
                            self.activeWordIndex = currentWord
                        }
                    }
                }
                
                self.updateNowPlayingPlaybackTime()
            }
        }
        
        // Track completion
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleTrackEnded()
            }
            .store(in: &cancellables)
    }
    
    public func togglePlayPause() {
        FluidHaptics.toggle()
        guard let player = player else {
            if let current = currentTrack {
                play(track: current, autoPlay: true, seekTo: currentTime > 0 ? currentTime : nil)
            } else if let first = queue.first {
                play(track: first)
            }
            return
        }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            ListeningAnalyticsManager.shared.flushPersistedStats()
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackTime()
        saveCurrentPlaybackState()
    }
    
    public func seek(to seconds: Double) {
        FluidHaptics.snap()
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: targetTime)
        currentTime = seconds
        lastSavedPosition = seconds
        updateNowPlayingPlaybackTime()
        saveCurrentPlaybackState()
    }
    
    public func next() {
        FluidHaptics.toggle()
        nextTrack()
    }
    
    public func nextTrack() {
        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            if let first = queue.first { play(track: first) }
            return
        }
        
        if currentIndex + 1 < queue.count {
            play(track: queue[currentIndex + 1])
            
            // Prefetch next radio batch when near end of queue
            if currentIndex + 2 >= queue.count && isAutoplayEnabled {
                Task {
                    if let last = self.queue.last {
                        let more = try? await InnerTubeClient.shared.fetchRadioTracks(for: last.id)
                        if let more = more {
                            for t in more {
                                if !self.queue.contains(where: { $0.id == t.id }) {
                                    self.queue.append(t)
                                }
                            }
                        }
                    }
                }
            }
        } else if isAutoplayEnabled {
            // Reached end of queue: Autoplay next track from YouTube Music Radio
            Task {
                await self.startRadio(for: current)
            }
        } else {
            // If autoplay is disabled, loop back to the start of the queue
            let nextIndex = (currentIndex + 1) % queue.count
            play(track: queue[nextIndex])
        }
    }
    
    public func previous() {
        FluidHaptics.toggle()
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        
        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            return
        }
        
        let prevIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        play(track: queue[prevIndex])
    }
    
    private func handleTrackEnded() {
        ListeningAnalyticsManager.shared.flushPersistedStats()
        if sleepTimerOption == .endOfTrack {
            setSleepTimer(.off)
            player?.pause()
            isPlaying = false
            return
        }
        
        if isRepeat {
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
        }
        
        nextTrack()
    }
    
    /// Starts playback of a track, clears previous search noise from queue, and populates with fresh algorithmic radio tracks
    public func playWithRadioAutoplay(track: Track) {
        self.queue = [track]
        self.play(track: track)
        
        if isAutoplayEnabled {
            Task {
                do {
                    let radioTracks = try await InnerTubeClient.shared.fetchRadioTracks(for: track.id)
                    guard !radioTracks.isEmpty else { return }
                    
                    for t in radioTracks {
                        if !self.queue.contains(where: { $0.id == t.id }) {
                            self.queue.append(t)
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[Failed to preload radio tracks]: \(error)")
                    #endif
                }
            }
        }
    }
    
    /// Algorithmic radio: Appends recommended tracks and continues playback
    public func startRadio(for track: Track) async {
        do {
            let radioTracks = try await InnerTubeClient.shared.fetchRadioTracks(for: track.id)
            guard !radioTracks.isEmpty else { return }
            
            for t in radioTracks {
                if !self.queue.contains(where: { $0.id == t.id }) {
                    self.queue.append(t)
                }
            }
            
            if let first = radioTracks.first {
                self.play(track: first)
            }
        } catch {
            #if DEBUG
            print("[Radio Autoplay Failed]: \(error)")
            #endif
        }
    }
    
    // MARK: - Queue Management
    
    public func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        queue.remove(at: index)
        saveCurrentPlaybackState()
    }
    
    public func clearQueue() {
        queue.removeAll()
        saveCurrentPlaybackState()
    }
    
    public func addToQueue(track: Track) {
        queue.append(track)
        saveCurrentPlaybackState()
    }
    
    public func playNext(track: Track) {
        if queue.isEmpty {
            queue.append(track)
        } else {
            queue.insert(track, at: 0)
        }
        saveCurrentPlaybackState()
    }
    
    // MARK: - Likes / Favorites
    
    public func isLiked(track: Track) -> Bool {
        return likedTracks.contains(where: { $0.id == track.id })
    }
    
    public func toggleLike(track: Track) {
        FluidHaptics.toggle()
        if let idx = likedTracks.firstIndex(where: { $0.id == track.id }) {
            likedTracks.remove(at: idx)
            if currentTrack?.id == track.id {
                currentTrack?.isLiked = false
            }
        } else {
            var liked = track
            liked.isLiked = true
            likedTracks.insert(liked, at: 0)
            if currentTrack?.id == track.id {
                currentTrack?.isLiked = true
                // Liking is explicit user commitment -> trigger auto-cache immediately
                triggerAutoSaveForCurrentTrack()
            }
        }
        saveLikedTracks()
    }
    
    // MARK: - Intentional Listening Auto-Cache (15-Second Skip Gate)
    
    public func triggerAutoSaveForCurrentTrack() {
        guard let track = self.currentTrack, !track.id.hasPrefix("local_") else { return }
        guard !hasAutoSavedCurrentTrack, !cacheManager.isCached(videoId: track.id) else {
            hasAutoSavedCurrentTrack = true
            return
        }
        
        hasAutoSavedCurrentTrack = true
        let trackToSave = track
        let remoteURL = self.currentStreamRemoteURL
        
        autoSaveTask?.cancel()
        autoSaveTask = Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                // 1. Fetch raw audio stream data
                var fetchedData: Data? = nil
                if let url = remoteURL {
                    var request = URLRequest(url: url)
                    request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    } else if let (data, response) = try? await URLSession.shared.data(from: url),
                              let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    }
                }
                
                if fetchedData == nil {
                    let (streamURL, _) = try await InnerTubeClient.shared.resolveStreamURL(for: trackToSave.id)
                    var request = URLRequest(url: streamURL)
                    request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    } else if let (data, response) = try? await URLSession.shared.data(from: streamURL),
                              let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    }
                }
                
                guard let audioData = fetchedData, audioData.count > 1024 else { return }
                
                // 2. Fetch lyrics if not yet loaded
                let lyrics = self.lyricLines.isEmpty ? await LRCLIBService.shared.fetchLyrics(for: trackToSave) : self.lyricLines
                
                // 3. Fetch artwork data
                var artworkData: Data? = nil
                if let artURL = trackToSave.artworkURL {
                    artworkData = try? await URLSession.shared.data(from: artURL).0
                }
                
                // 4. Pack and commit into compressed .sonorist bundle
                self.cacheManager.saveBundle(
                    track: trackToSave,
                    audioData: audioData,
                    lyrics: lyrics,
                    artworkData: artworkData
                )
                
                // 5. Update UI state on MainActor
                await MainActor.run {
                    if self.currentTrack?.id == trackToSave.id {
                        self.currentTrack?.isCached = true
                    }
                    LibraryViewModel.shared.loadOfflineTracks()
                }
            } catch {
                #if DEBUG
                print("[Auto-Cache Error]: \(error)")
                #endif
            }
        }
    }
    
    private func saveLikedTracks() {
        if let data = try? JSONEncoder().encode(likedTracks) {
            UserDefaults.standard.set(data, forKey: "SonoristLikedTracks")
        }
    }
    
    private func loadLikedTracks() {
        if let data = UserDefaults.standard.data(forKey: "SonoristLikedTracks") ?? UserDefaults.standard.data(forKey: "MetrolistLikedTracks"),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.likedTracks = tracks
        }
    }
    
    // MARK: - Explicit Track Download / Cache
    
    public func downloadTrack(track: Track) {
        guard !cacheManager.isCached(videoId: track.id) else { return }
        downloadingTrackIDs.insert(track.id)
        
        Task {
            do {
                let (streamURL, formatBadge) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id)
                var req = URLRequest(url: streamURL)
                req.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: req)
                
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    var updated = track
                    updated.audioFormat = formatBadge
                    self.cacheManager.cacheTrack(track: updated, data: data)
                }
            } catch {
                #if DEBUG
                print("[Download error]: \(error)")
                #endif
            }
            self.downloadingTrackIDs.remove(track.id)
        }
    }
    
    /// Removes a downloaded track from offline storage
    public func removeDownloadedTrack(track: Track) {
        self.cacheManager.removeCachedTrack(videoId: track.id)
    }
    
    // MARK: - Live Synced Lyrics (Multi-Provider, Translation & Music DNA)
    
    public func loadLyrics(for track: Track) async {
        self.isLoadingLyrics = true
        self.trackStory = nil
        self.activeWordIndex = -1
        
        // Restore per-track custom lyric offset if previously adjusted
        if UserDefaults.standard.object(forKey: "lyric_offset_\(track.id)") != nil {
            self.userLyricOffset = UserDefaults.standard.double(forKey: "lyric_offset_\(track.id)")
        } else {
            self.userLyricOffset = 0.0
        }
        
        if showTrackStory {
            loadTrackStory(for: track)
        }
        
        // Fast-path: Check offline .sonorist container first (0ms latency, zero network)
        if let cachedLyrics = cacheManager.getCachedLyrics(for: track.id) {
            self.lyricLines = cachedLyrics
            self.isLyricsSynced = cachedLyrics.first?.isSynced ?? true
            self.activeLyricIndex = 0
            self.isLoadingLyrics = false
            if showTranslation && lyricLines.contains(where: { $0.translation == nil || $0.translation!.isEmpty }) {
                translateCurrentLyrics()
            }
            return
        }
        
        let lines = await LRCLIBService.shared.fetchLyrics(for: track)
        self.lyricLines = lines
        self.isLyricsSynced = lines.first?.isSynced ?? true
        self.activeLyricIndex = 0
        self.isLoadingLyrics = false
        
        if showTranslation && lyricLines.contains(where: { $0.translation == nil || $0.translation!.isEmpty }) {
            translateCurrentLyrics()
        }
    }
    
    public func toggleTranslation() {
        FluidHaptics.toggle()
        showTranslation.toggle()
        if showTranslation && !lyricLines.isEmpty {
            let needsTranslation = lyricLines.contains(where: { $0.translation == nil || $0.translation!.isEmpty })
            if needsTranslation {
                translateCurrentLyrics()
            }
        }
    }
    
    public func translateCurrentLyrics() {
        guard !lyricLines.isEmpty else { return }
        isTranslatingLyrics = true
        let linesToTranslate = self.lyricLines
        let targetLang = self.targetTranslationLanguage
        Task {
            let translated = await LRCLIBService.shared.translateLines(linesToTranslate, targetLanguage: targetLang)
            await MainActor.run {
                self.lyricLines = translated
                self.isTranslatingLyrics = false
            }
        }
    }
    
    public func toggleRomanization() {
        FluidHaptics.toggle()
        showRomanization.toggle()
    }
    
    public func toggleTrackStory() {
        FluidHaptics.toggle()
        showTrackStory.toggle()
        if showTrackStory && trackStory == nil, let track = currentTrack {
            loadTrackStory(for: track)
        }
    }
    
    public func loadTrackStory(for track: Track) {
        isLoadingStory = true
        Task {
            let story = await LRCLIBService.shared.fetchTrackStory(for: track)
            await MainActor.run {
                if self.currentTrack?.id == track.id {
                    self.trackStory = story
                }
                self.isLoadingStory = false
            }
        }
    }
    
    public func adjustLyricOffset(by delta: Double) {
        FluidHaptics.tap()
        let updated = Double(round(100 * (self.userLyricOffset + delta)) / 100)
        self.userLyricOffset = max(-5.0, min(5.0, updated))
        if let trackId = currentTrack?.id {
            UserDefaults.standard.set(self.userLyricOffset, forKey: "lyric_offset_\(trackId)")
        }
    }
    
    public func resetLyricOffset() {
        FluidHaptics.toggle()
        self.userLyricOffset = 0.0
        if let trackId = currentTrack?.id {
            UserDefaults.standard.removeObject(forKey: "lyric_offset_\(trackId)")
        }
    }
    
    /// Instantly aligns lyric synchronization by snapping the selected line to the current playback time
    public func alignLyric(lineIndex: Int) {
        FluidHaptics.snap()
        guard lineIndex >= 0 && lineIndex < lyricLines.count else { return }
        let targetLine = lyricLines[lineIndex]
        let delta = self.currentTime - targetLine.time
        self.userLyricOffset = max(-10.0, min(10.0, Double(round(100 * delta) / 100)))
        if let trackId = currentTrack?.id {
            UserDefaults.standard.set(self.userLyricOffset, forKey: "lyric_offset_\(trackId)")
        }
    }
    
    public func seekToLyric(at index: Int) {
        FluidHaptics.snap()
        guard index >= 0 && index < lyricLines.count else { return }
        let targetTime = lyricLines[index].time
        seek(to: targetTime)
        activeLyricIndex = index
    }
    
    public var currentLyrics: [String] {
        if lyricLines.isEmpty {
            return ["No lyrics available for this track."]
        }
        return lyricLines.map { $0.text }
    }
    
    // MARK: - Sleep Timer Engine
    
    public func setSleepTimer(_ option: SleepTimerOption) {
        FluidHaptics.tap()
        self.sleepTimerOption = option
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        
        if isFadingForSleepTimer {
            self.volume = self.preFadeVolume
            self.isFadingForSleepTimer = false
        }
        
        guard let seconds = option.durationSeconds else {
            sleepTimerRemainingSeconds = 0
            return
        }
        
        self.sleepTimerRemainingSeconds = seconds
        self.preFadeVolume = self.volume
        
        sleepTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                
                if self.sleepTimerRemainingSeconds > 0 {
                    self.sleepTimerRemainingSeconds -= 1
                    
                    // Smooth logarithmic/linear 5-second fade-out before stopping
                    if self.sleepTimerRemainingSeconds <= 5 && self.sleepTimerRemainingSeconds > 0 {
                        self.isFadingForSleepTimer = true
                        let factor = Float(self.sleepTimerRemainingSeconds) / 5.0
                        self.volume = max(0, self.preFadeVolume * factor)
                    }
                    
                    if self.sleepTimerRemainingSeconds == 0 {
                        self.player?.pause()
                        self.isPlaying = false
                        self.volume = self.preFadeVolume
                        self.isFadingForSleepTimer = false
                        self.sleepTimerOption = .off
                        self.saveCurrentPlaybackState()
                        break
                    }
                }
            }
        }
    }
    
    public var formattedSleepTimerRemaining: String {
        guard sleepTimerRemainingSeconds > 0 else { return "" }
        let mins = sleepTimerRemainingSeconds / 60
        let secs = sleepTimerRemainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - macOS Now Playing & Remote Command Center Integration
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.isPlaying = true
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlaying(track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateNowPlayingPlaybackTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
