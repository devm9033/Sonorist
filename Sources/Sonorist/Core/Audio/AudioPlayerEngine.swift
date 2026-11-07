import Foundation
import AVFoundation
import MediaPlayer
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

/// Direction of track transition for fluid directional animations
public enum PlaybackSlideDirection: String, Sendable, Equatable {
    case forward
    case backward
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
    public static let trackDidCacheNotification = Notification.Name("SonoristTrackDidCacheNotification")

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
    public enum RepeatMode: String, CaseIterable, Codable {
        case off
        case all
        case one

        public var title: String {
            switch self {
            case .off: return "Repeat Off"
            case .all: return "Repeat All"
            case .one: return "Repeat One"
            }
        }

        public var systemImage: String {
            switch self {
            case .off, .all: return "repeat"
            case .one: return "repeat.1"
            }
        }
    }

    @Published public var queue: [Track] = []
    @Published public var isShuffle: Bool = false
    @Published public var repeatMode: RepeatMode = .off
    @Published public var isAutoplayEnabled: Bool = true
    @Published public var isPlayingFromOfflineLibrary: Bool = false
    @Published public var errorMessage: String?

    public var isRepeat: Bool {
        get { repeatMode != .off }
        set { repeatMode = newValue ? .all : .off }
    }

    private var unShuffledQueue: [Track] = []

    public func toggleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }

    public func toggleShuffle() {
        isShuffle.toggle()
        guard !queue.isEmpty else { return }

        if isShuffle {
            unShuffledQueue = queue
            if let current = currentTrack, let currentIdx = queue.firstIndex(where: { $0.id == current.id }) {
                let currentItem = queue[currentIdx]
                var remaining = queue
                remaining.remove(at: currentIdx)
                remaining.shuffle()
                self.queue = [currentItem] + remaining
            } else {
                self.queue.shuffle()
            }
        } else {
            if !unShuffledQueue.isEmpty {
                if let current = currentTrack, let currentIdx = unShuffledQueue.firstIndex(where: { $0.id == current.id }) {
                    let currentItem = unShuffledQueue[currentIdx]
                    var remaining = unShuffledQueue
                    remaining.remove(at: currentIdx)
                    self.queue = [currentItem] + remaining
                } else {
                    self.queue = unShuffledQueue
                }
                unShuffledQueue = []
            }
        }
    }

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
    @Published public var downloadProgress: [String: Double] = [:]

    // Audio Stream Quality Selection
    @Published public var selectedAudioQuality: AudioQuality = .standard
    @Published public var availableStreamOptions: [AudioStreamOption] = []

    // Audio Settings & Equalizer
    @Published public var equalizerPreset: String = "Flat"
    @Published public var isEqualizerEnabled: Bool = true
    @Published public var equalizerPreamp: Double = 0.0 // -12dB to +12dB
    @Published public var equalizerBands: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz

    public static let savedCrossfadeEnabledKey = "sonorist_saved_crossfade_enabled"
    public static let savedCrossfadeDurationKey = "sonorist_saved_crossfade_duration"

    @Published public var audioQualitySetting: String = "AAC 128kbps (Lossless Container)"
    @Published public var isAudioNormalized: Bool = true
    @Published public var isCrossfadeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isCrossfadeEnabled, forKey: Self.savedCrossfadeEnabledKey)
        }
    }
    @Published public var crossfadeDuration: Double = 4.0 {
        didSet {
            UserDefaults.standard.set(crossfadeDuration, forKey: Self.savedCrossfadeDurationKey)
        }
    }
    @Published public var isCrossfading: Bool = false
    @Published public var crossfadeProgress: Double = 0.0
    @Published public var outgoingTrack: Track? = nil
    @Published public var incomingTrack: Track? = nil
    @Published public var slideDirection: PlaybackSlideDirection = .forward

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

    public func setEqualizerPreset(_ name: String) {
        applyPreset(name)
    }

    public func setBand(index: Int, value: Double) {
        guard index >= 0 && index < equalizerBands.count else { return }
        equalizerBands[index] = max(-12.0, min(12.0, value))
        equalizerPreset = "Custom"
    }

    public func setEqualizerBand(index: Int, value: Double) {
        setBand(index: index, value: value)
    }

    private var player: AVPlayer?
    private var pendingHandoffPlayer: AVPlayer?
    private var timeObserverPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private let cacheManager = MediaCacheManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var playerItemCancellables = Set<AnyCancellable>()
    private var nowPlayingInfo: [String: Any] = [:]
    private var isRemoteCommandsConfigured: Bool = false

    private func removeCurrentTimeObserver() {
        if let token = timeObserverToken, let observingPlayer = timeObserverPlayer {
            observingPlayer.removeTimeObserver(token)
        }
        timeObserverToken = nil
        timeObserverPlayer = nil
    }

    // Intentional Listening Gate State
    public var continuousListeningSeconds: Double = 0.0
    public var hasAutoSavedCurrentTrack: Bool = false
    private var currentStreamRemoteURL: URL? = nil
    private var autoSaveTask: Task<Void, Never>? = nil
    private var stallRecoveryTask: Task<Void, Never>? = nil

    // Dual-Player Seamless Crossfade State
    private var outgoingPlayer: AVPlayer?
    private var isTransitioningCrossfade: Bool = false
    private var preloadedTrack: Track?
    private var preloadedPlayer: AVPlayer?
    private var preloadTask: Task<Void, Never>? = nil
    private var crossfadeTransitionTask: Task<Void, Never>? = nil
    private var manualCrossfadeResolveTask: Task<Void, Never>? = nil
    private var trackLoadingTask: Task<Void, Never>? = nil

    public init() {
        // 1. Restore persistent volume level across app launches
        if UserDefaults.standard.object(forKey: Self.savedVolumeKey) != nil {
            let savedVol = UserDefaults.standard.float(forKey: Self.savedVolumeKey)
            self.volume = savedVol
            if savedVol > 0 {
                self.preMuteVolume = savedVol
            }
        }

        loadLikedTracks()
        restoreSavedPlaybackState()

        if UserDefaults.standard.object(forKey: Self.savedCrossfadeEnabledKey) != nil {
            self.isCrossfadeEnabled = UserDefaults.standard.bool(forKey: Self.savedCrossfadeEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.savedCrossfadeDurationKey) != nil {
            let savedDur = UserDefaults.standard.double(forKey: Self.savedCrossfadeDurationKey)
            if savedDur >= 1.0 && savedDur <= 12.0 {
                self.crossfadeDuration = savedDur
            }
        }

        setupAppLifecycleObservers()
    }

    deinit {
        if let token = timeObserverToken, let observingPlayer = timeObserverPlayer {
            observingPlayer.removeTimeObserver(token)
        }
    }

    // MARK: - Audio Session Management

    public func assertAudioSession() {
        #if os(iOS)
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            do {
                if session.category != .playback || session.mode != .default {
                    try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
                }
                try session.setActive(true)
            } catch {
                #if DEBUG
                print("[Sonorist AudioSession] Failed to assert session: \(error)")
                #endif
            }
        }
        #endif
    }

    // MARK: - App Lifecycle Observers & State Persistence

    private func setupAppLifecycleObservers() {
        #if os(macOS)
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
        #elseif os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveCurrentPlaybackState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveCurrentPlaybackState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.saveCurrentPlaybackState()
                if self.isPlaying {
                    self.assertAudioSession()
                    self.updateNowPlayingPlaybackTime()
                }
                // Refresh Now Playing metadata at 0.6s and 2.5s to ensure SpringBoard/MediaRemote
                // catches the active route when transitioning into background (Trop pattern)
                for delay in [0.6, 2.5] {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard let self = self, UIApplication.shared.applicationState != .active else { return }
                        if self.isPlaying {
                            self.assertAudioSession()
                            self.updateNowPlayingPlaybackTime()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Self.artworkCache.removeAllObjects()
            }
            .store(in: &cancellables)
        #endif
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

        // NOTE: We intentionally do NOT call updateNowPlaying / updateNowPlayingPlaybackTime here.
        // Restoring state on cold launch fires before AVAudioSession is active and before
        // setupRemoteCommands() has run. Writing playbackRate=0 + playbackState=paused into
        // MPNowPlayingInfoCenter at this point causes SpringBoard to cache a "paused" session
        // and suppresses the Dynamic Island transport buttons when the user later plays a track.
        // Now Playing info is written by updateNowPlaying() inside startPlayer() once the
        // audio session is active and AVPlayer is ready to play.

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
        cancelCrossfade()

        // Instant fast-path: Check if target track is already pre-buffered and standing by
        if let prep = self.preloadedPlayer, let prepTrack = self.preloadedTrack, prepTrack.id == track.id, seekTo == nil {
            self.preloadedPlayer = nil
            self.preloadedTrack = nil
            self.promotePreloadedPlayer(prep, for: prepTrack, autoPlay: autoPlay)
            return
        }

        if track.id != preloadedTrack?.id {
            preloadTask?.cancel()
            preloadTask = nil
            preloadedPlayer?.pause()
            preloadedPlayer = nil
            preloadedTrack = nil
        }

        if let current = self.currentTrack, current.id != track.id {
            if let curIdx = queue.firstIndex(where: { $0.id == current.id }),
               let newIdx = queue.firstIndex(where: { $0.id == track.id }) {
                self.slideDirection = (newIdx >= curIdx) ? .forward : .backward
            }
        }

        // Keep currently playing song running seamlessly until incoming track is ready
        if autoPlay, let oldPlayer = self.player, self.isPlaying {
            self.pendingHandoffPlayer?.pause()
            self.pendingHandoffPlayer = oldPlayer
        } else {
            self.pendingHandoffPlayer?.pause()
            self.pendingHandoffPlayer = nil
            self.player?.pause()
        }

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

        // Ensure queue contains track for next/prev remote controls
        if !queue.contains(where: { $0.id == track.id }) {
            queue.insert(track, at: 0)
        }

        // Record into Listening Analytics
        let isCached = MediaCacheManager.shared.isCached(videoId: track.id)
        ListeningAnalyticsManager.shared.recordTrackStart(track: track, quality: selectedAudioQuality, isCached: isCached)

        let requestedTrackId = track.id
        trackLoadingTask?.cancel()
        trackLoadingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
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
                    if isPlayingFromOfflineLibrary {
                        #if DEBUG
                        print("[Offline Mode] Track \(track.title) (\(track.id)) not cached.")
                        #endif
                        self.isBuffering = false
                        self.isPlaying = false
                        self.errorMessage = "Track not available offline"
                        #if os(iOS)
                        MobileToastManager.shared.show(message: "Track Unavailable Offline", icon: "arrow.down.circle")
                        #endif
                        return
                    }
                    // 3. Resolve stream via InnerTube with user-selected quality
                    let (resolvedURL, badge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: self.selectedAudioQuality)
                    streamURL = resolvedURL
                    formatBadge = badge
                    self.availableStreamOptions = options
                    self.currentStreamRemoteURL = resolvedURL
                }

                // Race condition guard: verify this track is still current and task wasn't cancelled
                guard !Task.isCancelled, self.currentTrack?.id == requestedTrackId else { return }

                var updatedTrack = track
                updatedTrack.streamURL = streamURL
                updatedTrack.audioFormat = formatBadge
                updatedTrack.isCached = cacheManager.isCached(videoId: track.id)
                if let localArt = cacheManager.cachedArtworkURL(for: track.id) {
                    updatedTrack.artworkURL = localArt
                }
                updatedTrack.isLiked = isLiked(track: track)
                self.currentTrack = updatedTrack
                self.lyricLines = []
                self.activeLyricIndex = 0

                self.startPlayer(with: streamURL, track: updatedTrack, autoPlay: autoPlay, seekTo: seekTo)

                // Fetch synced lyrics in background
                await self.loadLyrics(for: updatedTrack)

                self.saveCurrentPlaybackState()
            } catch {
                guard !Task.isCancelled, self.currentTrack?.id == requestedTrackId else { return }
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

    // MARK: - Dual-Player Apple Music Crossfade Engine

    public func cancelCrossfade() {
        crossfadeTransitionTask?.cancel()
        crossfadeTransitionTask = nil
        manualCrossfadeResolveTask?.cancel()
        manualCrossfadeResolveTask = nil
        outgoingPlayer?.pause()
        outgoingPlayer = nil
        pendingHandoffPlayer?.pause()
        pendingHandoffPlayer = nil
        outgoingTrack = nil
        incomingTrack = nil
        crossfadeProgress = 0.0
        isTransitioningCrossfade = false
        isCrossfading = false
    }

    public func getNextTrackInQueue() -> Track? {
        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            return queue.first
        }
        if currentIndex + 1 < queue.count {
            return queue[currentIndex + 1]
        } else if repeatMode == .all && queue.count > 1 {
            return queue.first
        }
        return nil
    }

    public func getPreviousTrackInQueue() -> Track? {
        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        if currentIndex > 0 {
            return queue[currentIndex - 1]
        } else if repeatMode == .all && queue.count > 1 {
            return queue.last
        }
        return nil
    }

    /// Pre-warms the next track's audio stream and adjacent album artwork in RAM.
    /// Eliminates network wait times, buffering spinners, and visual frame drops when switching tracks.
    public func preloadNextTrack() {
        guard repeatMode != .one else { return }
        guard let nextTrack = getNextTrackInQueue() else { return }

        // 1. Preload artwork for next, current, and previous tracks into RAM
        ArtworkImageCache.shared.preload(url: nextTrack.artworkURL)
        if let current = currentTrack {
            ArtworkImageCache.shared.preload(url: current.artworkURL)
        }
        if let prev = getPreviousTrackInQueue() {
            ArtworkImageCache.shared.preload(url: prev.artworkURL)
        }

        // 2. If preloaded player is already standing by for this track, avoid re-fetching
        if preloadedTrack?.id == nextTrack.id && preloadedPlayer != nil {
            return
        }

        preloadTask?.cancel()
        preloadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.preloadTask = nil }

            do {
                let streamURL: URL
                var updatedNext = nextTrack
                if nextTrack.id.hasPrefix("local_") {
                    if let localURL = nextTrack.streamURL, localURL.isFileURL {
                        streamURL = localURL
                    } else {
                        return
                    }
                } else if let cached = self.cacheManager.preparePlaybackStream(for: nextTrack.id) {
                    streamURL = cached
                    updatedNext.isCached = true
                } else {
                    if self.isPlayingFromOfflineLibrary {
                        return
                    }
                    let (resolvedURL, badge, _) = try await InnerTubeClient.shared.resolveStreamURL(for: nextTrack.id, preferredQuality: self.selectedAudioQuality)
                    streamURL = resolvedURL
                    updatedNext.audioFormat = badge
                }

                if Task.isCancelled { return }

                let asset: AVURLAsset
                if streamURL.isFileURL {
                    asset = AVURLAsset(url: streamURL)
                } else {
                    asset = AVURLAsset(
                        url: streamURL,
                        options: [
                            "AVURLAssetHTTPHeaderFieldsKey": [
                                "User-Agent": "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"
                            ]
                        ]
                    )
                }

                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 30.0
                #if os(iOS)
                playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                #endif

                let prePlayer = AVPlayer(playerItem: playerItem)
                prePlayer.automaticallyWaitsToMinimizeStalling = true
                prePlayer.volume = 0.0
                #if os(iOS)
                prePlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
                prePlayer.preventsDisplaySleepDuringVideoPlayback = false
                #endif

                self.preloadedPlayer = prePlayer
                self.preloadedTrack = updatedNext

                // If dual-player crossfade threshold is active, trigger transition
                let remaining = self.duration - self.currentTime
                if self.isCrossfadeEnabled && self.crossfadeDuration > 0 && remaining <= self.crossfadeDuration && remaining > 0 && !self.isTransitioningCrossfade && self.isPlaying {
                    self.performCrossfadeTransitionIfNeeded()
                }
            } catch {
                #if DEBUG
                print("[Preload Next Track Failed]: \(error)")
                #endif
            }
        }
    }

    private func preloadNextTrackIfNeeded() {
        preloadNextTrack()
    }

    /// Instant promotion of pre-buffered AVPlayer when user triggers next track.
    /// Provides < 10ms audio start latency and zero network jitter.
    private func promotePreloadedPlayer(_ prep: AVPlayer, for track: Track, autoPlay: Bool = true) {
        if let current = self.currentTrack, current.id != track.id {
            if let curIdx = queue.firstIndex(where: { $0.id == current.id }),
               let newIdx = queue.firstIndex(where: { $0.id == track.id }) {
                self.slideDirection = (newIdx >= curIdx) ? .forward : .backward
            }
        }

        // Seamless audio handoff from old player
        if autoPlay, let oldPlayer = self.player, self.isPlaying {
            self.pendingHandoffPlayer?.pause()
            self.pendingHandoffPlayer = oldPlayer
        } else {
            self.pendingHandoffPlayer?.pause()
            self.pendingHandoffPlayer = nil
            self.player?.pause()
        }

        var updatedTrack = track
        updatedTrack.isLiked = isLiked(track: track)
        self.currentTrack = updatedTrack
        self.lyricLines = []
        self.activeLyricIndex = 0
        self.currentTime = 0.0
        self.lastSavedPosition = 0.0
        self.errorMessage = nil
        self.isBuffering = false

        // Add to history
        if !playHistory.contains(where: { $0.id == track.id }) {
            playHistory.insert(track, at: 0)
        }
        if !queue.contains(where: { $0.id == track.id }) {
            queue.insert(track, at: 0)
        }

        let isCached = MediaCacheManager.shared.isCached(videoId: track.id)
        ListeningAnalyticsManager.shared.recordTrackStart(track: track, quality: selectedAudioQuality, isCached: isCached)

        self.player = prep
        prep.volume = volume

        guard let item = prep.currentItem else {
            self.play(track: track, autoPlay: autoPlay)
            return
        }

        setupPlayerObservers(for: prep, playerItem: item, track: updatedTrack, autoPlay: autoPlay, seekTo: nil, isCrossfadeIncoming: false)

        if item.status == .readyToPlay {
            let itemDuration = item.duration.seconds
            self.duration = (itemDuration.isFinite && !itemDuration.isNaN && itemDuration > 0) ? itemDuration : track.durationSeconds
            if autoPlay {
                #if os(iOS)
                assertAudioSession()
                #endif
                prep.play()
                self.isPlaying = true
                self.updateNowPlaying(track: updatedTrack)

                // Fade out previous player smoothly over 100ms
                if let handoff = self.pendingHandoffPlayer {
                    self.pendingHandoffPlayer = nil
                    let curVol = handoff.volume
                    Task { @MainActor in
                        for s in 1...4 {
                            try? await Task.sleep(nanoseconds: 25_000_000)
                            handoff.volume = max(0, curVol * Float(4 - s) / 4.0)
                        }
                        handoff.pause()
                    }
                }
            }
        }

        // Fetch synced lyrics in background
        Task { @MainActor in
            await self.loadLyrics(for: updatedTrack)
        }

        saveCurrentPlaybackState()

        // Immediately start preloading the subsequent track in queue
        self.preloadNextTrack()
    }

    private func performCrossfadeTransitionIfNeeded() {
        guard isCrossfadeEnabled && crossfadeDuration > 0 && repeatMode != .one else { return }
        guard !isTransitioningCrossfade, isPlaying, duration > (crossfadeDuration + 1.0) else { return }
        guard let nextTrack = preloadedTrack ?? getNextTrackInQueue() else { return }

        // If preload is still resolving in background, let it finish and trigger transition
        if preloadedPlayer == nil && preloadTask != nil {
            return
        }

        if preloadedPlayer == nil {
            // Trigger preload if not yet active
            preloadNextTrackIfNeeded()
            let remaining = self.duration - self.currentTime
            if remaining > 1.0 {
                return
            }
        }

        isTransitioningCrossfade = true
        isCrossfading = true
        self.slideDirection = .forward

        preloadTask?.cancel()
        preloadTask = nil

        let oldPlayer = self.player
        self.outgoingPlayer = oldPlayer

        let incomingTrack = (preloadedTrack?.id == nextTrack.id) ? (preloadedTrack ?? nextTrack) : nextTrack
        let incomingPlayer: AVPlayer

        if let prep = self.preloadedPlayer, self.preloadedTrack?.id == incomingTrack.id {
            incomingPlayer = prep
            self.preloadedPlayer = nil
            self.preloadedTrack = nil
        } else {
            self.preloadedPlayer = nil
            self.preloadedTrack = nil
            isTransitioningCrossfade = false
            isCrossfading = false
            self.play(track: incomingTrack)
            return
        }

        incomingPlayer.volume = 0.0
        #if os(iOS)
        assertAudioSession()
        #endif
        incomingPlayer.play()

        let outgoing = self.currentTrack
        self.outgoingTrack = outgoing
        self.incomingTrack = incomingTrack
        self.crossfadeProgress = 0.0
        self.player = incomingPlayer
        self.duration = incomingTrack.durationSeconds
        self.currentTime = 0.0
        self.isPlaying = true
        self.isBuffering = false

        if let currentItem = incomingPlayer.currentItem {
            setupPlayerObservers(for: incomingPlayer, playerItem: currentItem, track: incomingTrack, autoPlay: true, isCrossfadeIncoming: true)
        }

        Task { [weak self] in
            await self?.loadLyrics(for: incomingTrack)
        }
        self.updateNowPlaying(track: incomingTrack)
        self.saveCurrentPlaybackState()

        let durationSecs = max(1.0, self.crossfadeDuration)
        let stepIntervalMs: UInt64 = 30
        let totalSteps = max(1, Int((durationSecs * 1000.0) / Double(stepIntervalMs)))

        crossfadeTransitionTask?.cancel()
        crossfadeTransitionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            for step in 1...totalSteps {
                try? await Task.sleep(nanoseconds: stepIntervalMs * 1_000_000)
                if Task.isCancelled { break }

                let progress = Double(step) / Double(totalSteps) // 0.0 -> 1.0
                self.crossfadeProgress = progress

                // Crossfade title & artist metadata smoothly at 50% midpoint
                if progress >= 0.5 && self.currentTrack?.id != incomingTrack.id {
                    self.currentTrack = incomingTrack
                }

                // Equal-Power Crossfade: cos(θ) & sin(θ) maintains constant acoustic power
                let angle = progress * (Double.pi / 2.0)
                let outGain = Float(cos(angle))
                let inGain = Float(sin(angle))

                let currentMaster = self.volume
                oldPlayer?.volume = max(0.0, min(currentMaster, currentMaster * outGain))
                incomingPlayer.volume = max(0.0, min(currentMaster, currentMaster * inGain))
            }

            oldPlayer?.pause()
            if self.outgoingPlayer === oldPlayer {
                self.outgoingPlayer = nil
            }
            if !self.isFadingForSleepTimer {
                incomingPlayer.volume = self.volume
            }
            self.currentTrack = incomingTrack
            self.duration = incomingTrack.durationSeconds
            self.isTransitioningCrossfade = false
            self.isCrossfading = false
            self.crossfadeProgress = 0.0
            self.outgoingTrack = nil
            self.incomingTrack = nil
        }
    }

    /// Crossfades from current playing track to target track (used for manual next/previous or swiping)
    public func crossfadeTo(track targetTrack: Track, direction: PlaybackSlideDirection, duration: Double = 2.0) {
        guard isCrossfadeEnabled && crossfadeDuration > 0,
              let outgoing = currentTrack,
              outgoing.id != targetTrack.id else {
            self.slideDirection = direction
            self.play(track: targetTrack)
            return
        }

        cancelCrossfade()

        let oldPlayer = self.player
        self.outgoingPlayer = oldPlayer
        self.outgoingTrack = outgoing
        self.incomingTrack = targetTrack
        self.slideDirection = direction
        self.isTransitioningCrossfade = true
        self.isCrossfading = true
        self.crossfadeProgress = 0.0

        manualCrossfadeResolveTask?.cancel()
        manualCrossfadeResolveTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            do {
                let streamURL: URL
                var updatedTarget = targetTrack
                if targetTrack.id.hasPrefix("local_") {
                    if let localURL = targetTrack.streamURL, localURL.isFileURL {
                        streamURL = localURL
                    } else {
                        self.play(track: targetTrack)
                        return
                    }
                } else if let cached = self.cacheManager.preparePlaybackStream(for: targetTrack.id) {
                    streamURL = cached
                } else {
                    let (resolvedURL, badge, _) = try await InnerTubeClient.shared.resolveStreamURL(for: targetTrack.id, preferredQuality: self.selectedAudioQuality)
                    streamURL = resolvedURL
                    updatedTarget.audioFormat = badge
                }

                guard self.isCrossfading, self.incomingTrack?.id == targetTrack.id else { return }

                let asset: AVURLAsset = streamURL.isFileURL ? AVURLAsset(url: streamURL) : AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"]])
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 60.0
                #if os(iOS)
                playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                #endif

                let incomingPlayer = AVPlayer(playerItem: playerItem)
                incomingPlayer.automaticallyWaitsToMinimizeStalling = true
                incomingPlayer.volume = 0.0
                #if os(iOS)
                self.assertAudioSession()
                incomingPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
                incomingPlayer.preventsDisplaySleepDuringVideoPlayback = false
                #endif
                incomingPlayer.play()

                self.player = incomingPlayer
                if let currentItem = incomingPlayer.currentItem {
                    self.setupPlayerObservers(for: incomingPlayer, playerItem: currentItem, track: updatedTarget, autoPlay: true, isCrossfadeIncoming: true)
                }

                Task { [weak self] in
                    await self?.loadLyrics(for: updatedTarget)
                }
                self.updateNowPlaying(track: updatedTarget)

                let durationSecs = min(2.5, max(1.0, self.crossfadeDuration))
                let stepIntervalMs: UInt64 = 30
                let totalSteps = max(1, Int((durationSecs * 1000.0) / Double(stepIntervalMs)))

                self.crossfadeTransitionTask?.cancel()
                self.crossfadeTransitionTask = Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    for step in 1...totalSteps {
                        try? await Task.sleep(nanoseconds: stepIntervalMs * 1_000_000)
                        if Task.isCancelled { break }

                        let progress = Double(step) / Double(totalSteps)
                        self.crossfadeProgress = progress

                        // Crossfade metadata title & artist at 50% midpoint
                        if progress >= 0.5 && self.currentTrack?.id != updatedTarget.id {
                            self.currentTrack = updatedTarget
                        }

                        let angle = progress * (Double.pi / 2.0)
                        let outGain = Float(cos(angle))
                        let inGain = Float(sin(angle))

                        let currentMaster = self.volume
                        oldPlayer?.volume = max(0.0, min(currentMaster, currentMaster * outGain))
                        incomingPlayer.volume = max(0.0, min(currentMaster, currentMaster * inGain))
                    }

                    oldPlayer?.pause()
                    if self.outgoingPlayer === oldPlayer {
                        self.outgoingPlayer = nil
                    }
                    if !self.isFadingForSleepTimer {
                        incomingPlayer.volume = self.volume
                    }
                    self.currentTrack = updatedTarget
                    self.duration = updatedTarget.durationSeconds
                    self.isTransitioningCrossfade = false
                    self.isCrossfading = false
                    self.crossfadeProgress = 0.0
                    self.outgoingTrack = nil
                    self.incomingTrack = nil
                }
            } catch {
                #if DEBUG
                print("[CrossfadeTo Failed, playing directly]: \(error)")
                #endif
                self.cancelCrossfade()
                self.play(track: targetTrack)
            }
        }
    }

    private func startPlayer(with url: URL, track: Track, autoPlay: Bool = true, seekTo: Double? = nil) {
        cancelCrossfade()
        removeCurrentTimeObserver()
        playerItemCancellables.removeAll()
        stallRecoveryTask?.cancel()

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
        // Aggressively buffer up to 60 seconds of forward audio to prevent cellular drops or rate limits
        playerItem.preferredForwardBufferDuration = 60.0
        #if os(iOS)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        #endif

        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.volume = volume
        #if os(iOS)
        newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        #endif
        self.player = newPlayer

        setupPlayerObservers(for: newPlayer, playerItem: playerItem, track: track, autoPlay: autoPlay, seekTo: seekTo, isCrossfadeIncoming: false)
    }

    private func setupPlayerObservers(for newPlayer: AVPlayer, playerItem: AVPlayerItem, track: Track, autoPlay: Bool = true, seekTo: Double? = nil, isCrossfadeIncoming: Bool = false) {
        removeCurrentTimeObserver()
        playerItemCancellables.removeAll()

        // 1. Observe status & initial ready-to-play
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    let itemDuration = playerItem.duration.seconds
                    self.duration = (itemDuration.isFinite && !itemDuration.isNaN && itemDuration > 0) ? itemDuration : track.durationSeconds
                    if let targetSeek = seekTo, targetSeek > 0 && targetSeek.isFinite && !targetSeek.isNaN {
                        let targetTime = CMTime(seconds: targetSeek, preferredTimescale: 600)
                        newPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = targetSeek
                    }
                    if autoPlay {
                        #if os(iOS)
                        self.assertAudioSession()
                        #endif
                        newPlayer.play()
                        self.isPlaying = true
                        self.updateNowPlaying(track: track)

                        // Seamless handoff: fade out the previous playing track now that the new track has begun
                        if let handoff = self.pendingHandoffPlayer {
                            self.pendingHandoffPlayer = nil
                            let curVol = handoff.volume
                            Task { @MainActor in
                                for s in 1...4 {
                                    try? await Task.sleep(nanoseconds: 25_000_000)
                                    handoff.volume = max(0, curVol * Float(4 - s) / 4.0)
                                }
                                handoff.pause()
                            }
                        }

                        if !isCrossfadeIncoming {
                            if self.isCrossfadeEnabled && self.crossfadeDuration > 0 && !self.isFadingForSleepTimer {
                                newPlayer.volume = 0.0
                                Task { @MainActor in
                                    let targetVol = self.volume
                                    let steps = 8
                                    for s in 1...steps {
                                        try? await Task.sleep(nanoseconds: 80_000_000)
                                        if Task.isCancelled || !self.isPlaying { break }
                                        let prog = Float(s) / Float(steps)
                                        newPlayer.volume = targetVol * prog
                                    }
                                    if !self.isFadingForSleepTimer {
                                        newPlayer.volume = targetVol
                                    }
                                }
                            } else if !self.isFadingForSleepTimer {
                                newPlayer.volume = self.volume
                            }
                        }
                        self.preloadNextTrack()
                    } else {
                        self.isPlaying = false
                        self.preloadNextTrack()
                    }
                case .failed:
                    let desc = playerItem.error?.localizedDescription ?? "Stream failed to load."
                    self.isBuffering = false
                    self.isPlaying = false

                    // Self-healing fallback: If offline file failed to open, try falling back to online stream
                    if let asset = playerItem.asset as? AVURLAsset, asset.url.isFileURL && !track.id.hasPrefix("local_") {
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
            .store(in: &playerItemCancellables)

        // 2. Observe buffer depletion & recovery
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                guard let self = self else { return }
                if isEmpty && self.isPlaying {
                    self.isBuffering = true
                }
            }
            .store(in: &playerItemCancellables)

        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likely in
                guard let self = self else { return }
                if likely {
                    self.isBuffering = false
                    if self.isPlaying && newPlayer.timeControlStatus != .playing {
                        newPlayer.play()
                    }
                }
            }
            .store(in: &playerItemCancellables)

        // 3. Observe playback stalling & trigger automatic smart stream recovery
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isBuffering = true
                #if DEBUG
                print("[AudioPlayerEngine]: AVPlayer playback stalled at \(self.currentTime)s. Attempting smart recovery...")
                #endif
                self.recoverFromStall()
            }
            .store(in: &playerItemCancellables)

        // 4. Observe item failure mid-stream (e.g. YouTube CDN severed connection)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notif in
                guard let self = self else { return }
                let error = notif.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                #if DEBUG
                print("[AudioPlayerEngine]: Item failed to play to end time: \(String(describing: error)). Auto-recovering...")
                #endif
                self.recoverFromStall(forceStreamRefresh: true)
            }
            .store(in: &playerItemCancellables)

        // 5. Observe player timeControlStatus for accurate buffering indicator
        newPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .playing:
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    if self.isPlaying {
                        self.isBuffering = true
                    }
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &playerItemCancellables)

        // Periodic time observer for smooth UI scrubbing & lyric line synchronization (250ms interval)
        removeCurrentTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = time.seconds
            guard secs.isFinite && !secs.isNaN && secs >= 0 else { return }

            if !self.isDraggingScrubber {
                self.currentTime = secs
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

                    // Seamless Dual-Player Apple Music Crossfade
                    if self.isCrossfadeEnabled && self.crossfadeDuration > 0 && self.repeatMode != .one && self.duration > (self.crossfadeDuration + 1.0) && !self.isFadingForSleepTimer && !self.isTransitioningCrossfade {
                        let remaining = self.duration - secs
                        if remaining <= max(25.0, self.crossfadeDuration + 10.0) && remaining > self.crossfadeDuration {
                            self.preloadNextTrackIfNeeded()
                        } else if remaining <= self.crossfadeDuration && remaining > 0 {
                            self.performCrossfadeTransitionIfNeeded()
                        }
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
        }
        timeObserverPlayer = newPlayer

        // Track completion
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.player !== newPlayer { return }
                if self.isTransitioningCrossfade { return }
                self.handleTrackEnded()
            }
            .store(in: &playerItemCancellables)
    }

    /// Smart self-healing recovery when audio stalls or buffers freeze mid-stream
    public func recoverFromStall(forceStreamRefresh: Bool = false) {
        stallRecoveryTask?.cancel()
        stallRecoveryTask = Task { @MainActor in
            guard self.isPlaying, let current = self.currentTrack else { return }

            // 1. If not forcing a full stream refresh, give AVPlayer a 2-second grace period to resume buffering
            if !forceStreamRefresh {
                self.player?.play()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }

                // If it successfully resumed playing, we're all set!
                if self.player?.timeControlStatus == .playing {
                    self.isBuffering = false
                    return
                }
            }

            // 2. If it's a local/offline file, just seek to current position and restart
            if current.isCached || current.id.hasPrefix("local_") {
                let savedTime = self.currentTime
                await self.player?.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                self.player?.play()
                self.isBuffering = false
                return
            }

            // 3. For remote YouTube streams: YouTube CDN connections can terminate or throttle mid-song.
            // Seamlessly fetch a fresh, unthrottled streaming URL and resume at the exact second!
            #if DEBUG
            print("[AudioPlayerEngine]: Refreshing live stream URL to recover stalled playback for '\(current.title)' at \(self.currentTime)s")
            #endif
            do {
                let (freshURL, badge, options) = try await InnerTubeClient.shared.resolveStreamURL(for: current.id, preferredQuality: self.selectedAudioQuality)
                if Task.isCancelled { return }
                var updated = current
                updated.streamURL = freshURL
                updated.audioFormat = badge
                self.currentTrack = updated
                self.availableStreamOptions = options
                self.currentStreamRemoteURL = freshURL
                let resumeTime = self.currentTime
                self.startPlayer(with: freshURL, track: updated, autoPlay: true, seekTo: resumeTime)
            } catch {
                #if DEBUG
                print("[AudioPlayerEngine]: Stall recovery stream refresh failed: \(error)")
                #endif
                self.player?.play()
            }
        }
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
            outgoingPlayer?.pause()
            pendingHandoffPlayer?.pause()
            pendingHandoffPlayer = nil
            isPlaying = false
            ListeningAnalyticsManager.shared.flushPersistedStats()
            updateNowPlayingPlaybackTime()
        } else {
            #if os(iOS)
            assertAudioSession()
            #endif
            player.play()
            outgoingPlayer?.play()
            isPlaying = true
            if let current = currentTrack {
                updateNowPlaying(track: current)
            } else {
                updateNowPlayingPlaybackTime()
            }
        }
        saveCurrentPlaybackState()
    }

    public func pause() {
        if isPlaying {
            togglePlayPause()
        }
    }

    public func resume() {
        if !isPlaying {
            togglePlayPause()
        }
    }

    public func seek(to seconds: Double) {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return }
        let clampedSeconds = max(0.0, min(seconds, duration > 0 ? duration : seconds))
        cancelCrossfade()
        if !isFadingForSleepTimer {
            player?.volume = volume
        }
        FluidHaptics.snap()
        let targetTime = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player?.seek(to: targetTime)
        currentTime = clampedSeconds
        lastSavedPosition = clampedSeconds
        updateNowPlayingPlaybackTime()
        saveCurrentPlaybackState()
    }

    public func next() {
        FluidHaptics.toggle()
        cancelCrossfade()
        slideDirection = .forward
        nextTrack()
    }

    /// Immediate forceful track advance (used when user manually flicks album art)
    public func forceNextTrack() {
        FluidHaptics.toggle()
        cancelCrossfade()
        trackLoadingTask?.cancel()
        slideDirection = .forward
        nextTrack()
    }

    public func nextTrack() {
        cancelCrossfade()
        slideDirection = .forward
        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            if let first = queue.first { play(track: first) }
            return
        }

        if currentIndex + 1 < queue.count {
            play(track: queue[currentIndex + 1])

            // Prefetch next radio batch when near end of queue (Only when NOT playing offline library)
            if !isPlayingFromOfflineLibrary && currentIndex + 2 >= queue.count && isAutoplayEnabled {
                Task { @MainActor in
                    if let last = self.queue.last {
                        let more = try? await InnerTubeClient.shared.fetchRadioTracks(for: last.id)
                        if let more = more {
                            for t in more {
                                if !self.queue.contains(where: { $0.id == t.id }) {
                                    var trackToAdd = t
                                    if let localArt = self.cacheManager.cachedArtworkURL(for: t.id) {
                                        trackToAdd.artworkURL = localArt
                                    }
                                    trackToAdd.isCached = self.cacheManager.isCached(videoId: t.id)
                                    self.queue.append(trackToAdd)
                                }
                            }
                        }
                    }
                }
            }
        } else if repeatMode == .all {
            // Repeat all tracks: loop back to beginning of queue
            play(track: queue[0])
        } else if !isPlayingFromOfflineLibrary && isAutoplayEnabled {
            // Reached end of queue in Online mode: Autoplay next track from YouTube Music Radio
            Task { @MainActor in
                await self.startRadio(for: current)
            }
        } else {
            // Repeat is OFF: On explicit next button tap, wrap around
            let nextIndex = (currentIndex + 1) % queue.count
            play(track: queue[nextIndex])
        }
    }

    public func previous() {
        FluidHaptics.toggle()
        if currentTime > 3.0 {
            cancelCrossfade()
            seek(to: 0)
            return
        }

        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            cancelCrossfade()
            seek(to: 0)
            return
        }

        if currentIndex > 0 {
            let prev = queue[currentIndex - 1]
            cancelCrossfade()
            slideDirection = .backward
            play(track: prev)
        } else if repeatMode == .all && queue.count > 1 {
            let prev = queue[queue.count - 1]
            cancelCrossfade()
            slideDirection = .backward
            play(track: prev)
        } else {
            // At start of queue: rewind to beginning of track (standard Apple Music behavior)
            cancelCrossfade()
            seek(to: 0)
        }
    }

    /// Immediate forceful track jump back (used when user manually flicks album art)
    public func forcePreviousTrack() {
        FluidHaptics.toggle()
        cancelCrossfade()
        trackLoadingTask?.cancel()
        slideDirection = .backward
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }

        guard !queue.isEmpty, let current = currentTrack,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            seek(to: 0)
            return
        }

        if currentIndex > 0 {
            play(track: queue[currentIndex - 1])
        } else if repeatMode == .all && queue.count > 1 {
            play(track: queue[queue.count - 1])
        } else {
            // At start of queue: rewind to beginning of track
            seek(to: 0)
        }
    }

    private func handleTrackEnded() {
        if isTransitioningCrossfade { return }
        cancelCrossfade()
        self.isCrossfading = false
        if !self.isFadingForSleepTimer {
            self.player?.volume = self.volume
        }
        ListeningAnalyticsManager.shared.flushPersistedStats()
        if sleepTimerOption == .endOfTrack {
            setSleepTimer(.off)
            player?.pause()
            isPlaying = false
            return
        }

        switch repeatMode {
        case .one:
            // Repeat one track indefinitely
            seek(to: 0)
            player?.play()
            isPlaying = true
            return

        case .all:
            guard !queue.isEmpty, let current = currentTrack,
                  let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
                return
            }
            if currentIndex + 1 < queue.count {
                play(track: queue[currentIndex + 1])
            } else {
                // Loop back to the start of the queue
                play(track: queue[0])
            }

        case .off:
            guard !queue.isEmpty, let current = currentTrack,
                  let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
                return
            }
            if currentIndex + 1 < queue.count {
                play(track: queue[currentIndex + 1])
            } else if !isPlayingFromOfflineLibrary && isAutoplayEnabled {
                // Autoplay YouTube Radio continuation
                Task { @MainActor in
                    await self.startRadio(for: current)
                }
            } else {
                // Reached end of offline library or queue with repeat OFF: Stop playback!
                player?.pause()
                isPlaying = false
                seek(to: 0)
            }
        }
    }

    /// Starts playback of a track strictly from local offline library.
    /// Only downloaded tracks (.sonorist bundles) or local disk imports are queued.
    /// Never queries YouTube Music or fetches radio tracks.
    public func playFromOfflineLibrary(tracks: [Track], selectedTrack: Track) {
        self.isPlayingFromOfflineLibrary = true
        let offlineTracks = tracks.filter { $0.id.hasPrefix("local_") || cacheManager.isCached(videoId: $0.id) }
        guard !offlineTracks.isEmpty else {
            #if os(iOS)
            MobileToastManager.shared.show(message: "No Offline Songs", icon: "arrow.down.circle")
            #endif
            self.isPlayingFromOfflineLibrary = false
            return
        }

        let target = offlineTracks.first(where: { $0.id == selectedTrack.id }) ?? offlineTracks[0]

        if let idx = offlineTracks.firstIndex(where: { $0.id == target.id }) {
            self.queue = Array(offlineTracks[idx...]) + Array(offlineTracks[..<idx])
        } else {
            self.queue = offlineTracks
        }

        if isShuffle {
            var remaining = self.queue.filter { $0.id != target.id }
            remaining.shuffle()
            self.queue = [target] + remaining
        }

        self.play(track: target)
    }

    /// Starts playback of a track from a general playlist (e.g. Liked songs, custom collections).
    /// Enables online stream resolution while taking instant offline fast-path when cached.
    public func playFromPlaylist(tracks: [Track], selectedTrack: Track) {
        self.isPlayingFromOfflineLibrary = false
        guard !tracks.isEmpty else { return }

        let target = tracks.first(where: { $0.id == selectedTrack.id }) ?? tracks[0]

        if let idx = tracks.firstIndex(where: { $0.id == target.id }) {
            self.queue = Array(tracks[idx...]) + Array(tracks[..<idx])
        } else {
            self.queue = tracks
        }

        if isShuffle {
            var remaining = self.queue.filter { $0.id != target.id }
            remaining.shuffle()
            self.queue = [target] + remaining
        }

        self.play(track: target)
    }

    /// Starts playback of a track, clears previous queue, and builds YouTube Music's true algorithmic radio queue
    public func playFromSearch(results: [Track] = [], selectedTrack: Track) {
        self.isPlayingFromOfflineLibrary = false
        var seedTrack = selectedTrack
        if let localArt = cacheManager.cachedArtworkURL(for: selectedTrack.id) {
            seedTrack.artworkURL = localArt
        }
        seedTrack.isCached = cacheManager.isCached(videoId: selectedTrack.id)

        self.queue = [seedTrack]
        self.play(track: seedTrack)

        // Immediately query YouTube Music algorithmic radio seeded by the ongoing track
        Task { @MainActor in
            do {
                let radioTracks = try await InnerTubeClient.shared.fetchRadioTracks(for: selectedTrack.id)
                guard !radioTracks.isEmpty else { return }

                var tracksToAdd: [Track] = []
                for t in radioTracks {
                    if !self.queue.contains(where: { $0.id == t.id }) {
                        var trackToAdd = t
                        if let localArt = self.cacheManager.cachedArtworkURL(for: t.id) {
                            trackToAdd.artworkURL = localArt
                        }
                        trackToAdd.isCached = self.cacheManager.isCached(videoId: t.id)
                        tracksToAdd.append(trackToAdd)
                    }
                }
                if self.isShuffle {
                    tracksToAdd.shuffle()
                }
                self.queue.append(contentsOf: tracksToAdd)
                self.saveCurrentPlaybackState()
            } catch {
                #if DEBUG
                print("[Radio Queue Append Failed]: \(error)")
                #endif
            }
        }
    }

    /// Starts playback of a track, clears previous search noise from queue, and populates with fresh algorithmic radio tracks
    public func playWithRadioAutoplay(track: Track) {
        self.isPlayingFromOfflineLibrary = false
        self.queue = [track]
        self.play(track: track)

        if isAutoplayEnabled {
            Task { @MainActor in
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

    public func removeFromQueue(atOffsets offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        saveCurrentPlaybackState()
    }

    public func removeFromQueue(id: String) {
        queue.removeAll(where: { $0.id == id })
        saveCurrentPlaybackState()
    }

    public func moveInQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        saveCurrentPlaybackState()
    }

    public func clearQueue() {
        queue.removeAll()
        saveCurrentPlaybackState()
    }

    public func addToQueue(track: Track) {
        var queuedTrack = track
        if let localArt = cacheManager.cachedArtworkURL(for: track.id) {
            queuedTrack.artworkURL = localArt
        }
        queuedTrack.isCached = cacheManager.isCached(videoId: track.id)
        queue.append(queuedTrack)
        saveCurrentPlaybackState()
    }

    public func playNext(track: Track) {
        var queuedTrack = track
        if let localArt = cacheManager.cachedArtworkURL(for: track.id) {
            queuedTrack.artworkURL = localArt
        }
        queuedTrack.isCached = cacheManager.isCached(videoId: track.id)

        if let current = currentTrack, let idx = queue.firstIndex(where: { $0.id == current.id }) {
            queue.insert(queuedTrack, at: idx + 1)
        } else {
            queue.insert(queuedTrack, at: 0)
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
        guard !isPlayingFromOfflineLibrary else { return }
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
                if let url = remoteURL, let safeURL = SecurityAudit.validateURL(url.absoluteString) {
                    var request = URLRequest(url: safeURL)
                    request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    } else if let (data, response) = try? await URLSession.shared.data(from: safeURL),
                              let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                        fetchedData = data
                    }
                }

                if fetchedData == nil {
                    let (streamURL, _) = try await InnerTubeClient.shared.resolveStreamURL(for: trackToSave.id)
                    if let safeStream = SecurityAudit.validateURL(streamURL.absoluteString) {
                        var request = URLRequest(url: safeStream)
                        request.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
                        if let (data, response) = try? await URLSession.shared.data(for: request),
                           let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                            fetchedData = data
                        } else if let (data, response) = try? await URLSession.shared.data(from: safeStream),
                                  let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), data.count > 1024 {
                            fetchedData = data
                        }
                    }
                }

                guard let audioData = fetchedData, audioData.count > 1024 else { return }

                // 2. Fetch lyrics if not yet loaded
                let lyrics = self.lyricLines.isEmpty ? await LRCLIBService.shared.fetchLyrics(for: trackToSave) : self.lyricLines

                // 3. Fetch artwork data
                var artworkData: Data? = nil
                if let artURL = trackToSave.artworkURL, let safeArt = SecurityAudit.validateURL(artURL.absoluteString) {
                    artworkData = try? await URLSession.shared.data(from: safeArt).0
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
                    NotificationCenter.default.post(name: Self.trackDidCacheNotification, object: trackToSave)
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

    private final class TrackDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Double) -> Void
        private let onCompletion: @Sendable (Data?, Error?) -> Void
        private var buffer = Data()
        private var expectedLength: Int64 = 0

        init(onProgress: @escaping @Sendable (Double) -> Void, onCompletion: @escaping @Sendable (Data?, Error?) -> Void) {
            self.onProgress = onProgress
            self.onCompletion = onCompletion
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.expectedLength = response.expectedContentLength
            if expectedLength > 0 {
                buffer.reserveCapacity(min(Int(expectedLength), 50 * 1024 * 1024))
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            if expectedLength > 0 {
                let ratio = Double(buffer.count) / Double(expectedLength)
                onProgress(min(0.99, ratio))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                onCompletion(nil, error)
            } else {
                onCompletion(buffer, nil)
            }
        }
    }

    public func downloadTrack(track: Track) {
        guard !cacheManager.isCached(videoId: track.id) else { return }
        downloadingTrackIDs.insert(track.id)
        downloadProgress[track.id] = 0.05

        Task { @MainActor in
            do {
                let (streamURL, formatBadge, _) = try await InnerTubeClient.shared.resolveStreamURL(for: track.id, preferredQuality: self.selectedAudioQuality)
                var req = URLRequest(url: streamURL)
                req.setValue("com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")

                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    let delegate = TrackDownloadDelegate(
                        onProgress: { ratio in
                            DispatchQueue.main.async {
                                self.downloadProgress[track.id] = ratio
                            }
                        },
                        onCompletion: { resultData, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else if let resultData = resultData {
                                continuation.resume(returning: resultData)
                            } else {
                                continuation.resume(throwing: URLError(.unknown))
                            }
                        }
                    )
                    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                    let task = session.dataTask(with: req)
                    task.resume()
                }

                self.downloadProgress[track.id] = 1.0

                // Allow user to perceptibly see 100% completion ring before transitioning to badge
                try? await Task.sleep(nanoseconds: 400_000_000)

                var updated = track
                updated.audioFormat = formatBadge
                updated.isCached = true
                self.cacheManager.cacheTrack(track: updated, data: data)

                if self.currentTrack?.id == track.id {
                    self.currentTrack?.isCached = true
                }
                for i in 0..<self.queue.count {
                    if self.queue[i].id == track.id {
                        self.queue[i].isCached = true
                    }
                }
                for i in 0..<self.playHistory.count {
                    if self.playHistory[i].id == track.id {
                        self.playHistory[i].isCached = true
                    }
                }
                for i in 0..<self.likedTracks.count {
                    if self.likedTracks[i].id == track.id {
                        self.likedTracks[i].isCached = true
                    }
                }
                NotificationCenter.default.post(name: Self.trackDidCacheNotification, object: track.id)
                #if os(iOS)
                MobileToastManager.shared.show(message: "Downloaded for Offline", icon: "arrow.down.circle.fill")
                #endif
            } catch {
                #if DEBUG
                print("[Download error]: \(error)")
                #endif
            }
            self.downloadingTrackIDs.remove(track.id)
            self.downloadProgress.removeValue(forKey: track.id)
        }
    }

    /// Removes a downloaded track from offline storage
    public func removeDownloadedTrack(track: Track) {
        self.cacheManager.removeCachedTrack(videoId: track.id)

        if self.currentTrack?.id == track.id {
            self.currentTrack?.isCached = false
        }
        for i in 0..<self.queue.count {
            if self.queue[i].id == track.id {
                self.queue[i].isCached = false
            }
        }
        for i in 0..<self.playHistory.count {
            if self.playHistory[i].id == track.id {
                self.playHistory[i].isCached = false
            }
        }
        for i in 0..<self.likedTracks.count {
            if self.likedTracks[i].id == track.id {
                self.likedTracks[i].isCached = false
            }
        }
        NotificationCenter.default.post(name: Self.trackDidCacheNotification, object: track.id)
        #if os(iOS)
        MobileToastManager.shared.show(message: "Removed from Downloads", icon: "trash")
        #endif
    }

    /// Completely purges all offline library bundles, cache files, and extracted artwork
    public func clearAllOfflineDownloads() {
        cacheManager.clearCache()
        for i in 0..<self.queue.count {
            self.queue[i].isCached = false
        }
        for i in 0..<self.playHistory.count {
            self.playHistory[i].isCached = false
        }
        for i in 0..<self.likedTracks.count {
            self.likedTracks[i].isCached = false
        }
        if var current = self.currentTrack {
            current.isCached = false
            self.currentTrack = current
        }
        saveCurrentPlaybackState()
    }

    // MARK: - Live Synced Lyrics (Multi-Provider, Translation & Music DNA)

    public func loadLyrics(for track: Track) async {
        self.isLoadingLyrics = true
        self.lyricLines = []
        self.activeLyricIndex = 0
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
            guard self.currentTrack?.id == track.id else { return }
            self.lyricLines = cachedLyrics
            self.isLyricsSynced = cachedLyrics.first?.isSynced ?? true
            self.activeLyricIndex = 0
            self.isLoadingLyrics = false
            if showTranslation && lyricLines.contains(where: { ($0.translation?.isEmpty ?? true) }) {
                translateCurrentLyrics()
            }
            return
        }

        // In offline mode, do not perform external LRCLIB network requests
        if isPlayingFromOfflineLibrary {
            self.isLoadingLyrics = false
            return
        }

        let lines = await LRCLIBService.shared.fetchLyrics(for: track)
        guard self.currentTrack?.id == track.id else { return }
        self.lyricLines = lines
        self.isLyricsSynced = lines.first?.isSynced ?? true
        self.activeLyricIndex = 0
        self.isLoadingLyrics = false

        if showTranslation && lyricLines.contains(where: { ($0.translation?.isEmpty ?? true) }) {
            translateCurrentLyrics()
        }
    }

    public func toggleTranslation() {
        FluidHaptics.toggle()
        showTranslation.toggle()
        if showTranslation && !lyricLines.isEmpty {
            let needsTranslation = lyricLines.contains(where: { ($0.translation?.isEmpty ?? true) })
            if needsTranslation && !isTranslatingLyrics {
                translateCurrentLyrics()
            }
        }
    }

    public func translateCurrentLyrics() {
        guard !lyricLines.isEmpty, !isTranslatingLyrics else { return }
        guard let trackId = currentTrack?.id else { return }
        isTranslatingLyrics = true
        let linesToTranslate = self.lyricLines
        let targetLang = self.targetTranslationLanguage

        Task.detached(priority: .userInitiated) {
            let translated = await LRCLIBService.shared.translateLines(linesToTranslate, targetLanguage: targetLang)
            await MainActor.run {
                if self.currentTrack?.id == trackId {
                    self.lyricLines = translated
                }
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
                        self.cancelCrossfade()
                        self.player?.pause()
                        self.outgoingPlayer?.pause()
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

    private func cleanDisplayTitle(_ title: String) -> String {
        var cleaned = title
        let patterns = [
            #"\((From|from|FROM)[^\)]+\)"#,
            #"\[(From|from|FROM)[^\]]+\]"#,
            #"\((Official )?(Music )?Video\)"#,
            #"\[(Official )?(Music )?Video\]"#,
            #"\((Official )?Audio\)"#,
            #"\[(Official )?Audio\]"#,
            #"\(Lyrics?\)"#,
            #"\[Lyrics?\]"#
        ]
        for pat in patterns {
            if let reg = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = reg.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if os(iOS)
    private static let placeholderArtwork: UIImage? = {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.18, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if let note = UIImage(systemName: "music.note") {
                UIColor.white.withAlphaComponent(0.65).set()
                note.draw(in: CGRect(x: 100, y: 100, width: 100, height: 100))
            }
        }
    }()
    #endif

    public func setupRemoteCommands() {
        guard !isRemoteCommandsConfigured else { return }
        isRemoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        #if os(iOS)
        // beginReceivingRemoteControlEvents MUST be called synchronously BEFORE registering
        // any command targets. The async dispatch was causing targets to be registered before
        // SpringBoard acknowledged the app as a remote control receiver, silently discarding
        // all command registrations and suppressing Dynamic Island transport buttons.
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif

        // Clear any previous targets to prevent duplicates
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)

        // togglePlayPauseCommand MUST be enabled — SpringBoard uses it to render the
        // play/pause button in the expanded Dynamic Island and Lock Screen media card.
        // Discrete playCommand + pauseCommand handle the actual play/pause action routing;
        // togglePlayPauseCommand is what makes the button *visible*.
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            if self.isPlaying { self.pause() } else { self.resume() }
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            #if os(iOS)
            self?.assertAudioSession()
            #endif
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    private func updateNowPlaying(track: Track) {
        let displayTitle = cleanDisplayTitle(track.title)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle.isEmpty ? track.title : displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: max(1.0, duration > 0 ? duration : track.durationSeconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        let rawAlbum = (track.album ?? "").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        if !rawAlbum.isEmpty && rawAlbum != track.title && rawAlbum.lowercased() != "youtube music" && rawAlbum != "," {
            info[MPMediaItemPropertyAlbumTitle] = rawAlbum
        }

        #if os(iOS)
        if let placeholder = Self.placeholderArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: placeholder.size) { _ in placeholder }
        }
        #endif

        self.nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo

        if let artworkURL = track.artworkURL {
            loadArtworkForNowPlaying(url: artworkURL, trackId: track.id)
        }
    }

    private func updateNowPlayingPlaybackTime() {
        guard !nowPlayingInfo.isEmpty else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private static let artworkCache: NSCache<NSString, MPMediaItemArtwork> = {
        let cache = NSCache<NSString, MPMediaItemArtwork>()
        cache.countLimit = 30
        return cache
    }()

    private func loadArtworkForNowPlaying(url: URL, trackId: String) {
        let urlKey = url.absoluteString as NSString
        if let cached = Self.artworkCache.object(forKey: urlKey) {
            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            return
        }

        #if os(iOS)
        // If it's a local file URL (e.g. offline downloaded track), load synchronously
        if url.isFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
            let artwork = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
            Self.artworkCache.setObject(artwork, forKey: urlKey)
            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            return
        }
        #elseif os(macOS)
        if url.isFileURL, let nsImage = NSImage(contentsOfFile: url.path) {
            let artwork = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }
            Self.artworkCache.setObject(artwork, forKey: urlKey)
            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            return
        }
        #endif

        guard let safeURL = SecurityAudit.validateURL(url.absoluteString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: safeURL)
                #if os(iOS)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        guard self.currentTrack?.id == trackId else { return }
                        let artwork = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
                        Self.artworkCache.setObject(artwork, forKey: urlKey)
                        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
                    }
                }
                #elseif os(macOS)
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        guard self.currentTrack?.id == trackId else { return }
                        let artwork = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }
                        Self.artworkCache.setObject(artwork, forKey: urlKey)
                        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
                    }
                }
                #endif
            } catch {
                // Ignore transient artwork fetch failures
            }
        }
    }
}
