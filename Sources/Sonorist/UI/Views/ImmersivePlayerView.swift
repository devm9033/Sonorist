import SwiftUI

@MainActor
public final class ImmersiveViewModel: ObservableObject {
    public static let shared = ImmersiveViewModel()
    @Published public var showSleepTimerMenu: Bool = false
    @Published public var compactTab: Int = 0 // 0: Now Playing, 1: Synced Lyrics
    public init() {}
}

/// Full-window immersive Apple Music-style Now Playing experience
/// Features real-time fluid ambient artwork glow, interactive rolling karaoke lyrics, and complete playback controls.
/// Fully adaptive to macOS Light (White), Dark, and System appearance modes.
public struct ImmersivePlayerView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var viewModel = ImmersiveViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool { colorScheme == .light }
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geo in
            let isShort = geo.size.height < 540
            let isNarrow = geo.size.width < 840
            
            // MARK: - Content Layout
            VStack(spacing: isShort ? 6 : (isNarrow ? 10 : 14)) {
                // Invisible Keyboard Shortcuts for Esc and ⌘F to exit Now Playing
                Button("") {
                    withAnimation(FluidTheme.fluidSpring) {
                        player.isImmersiveViewActive = false
                    }
                }
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut("f", modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)
                
                // In Ultra-Compact Mode (< 640 width), render the segmented tab picker ("Now Playing" / "Lyrics")
                if geo.size.width < 640 {
                    compactSegmentedPicker
                        .padding(.top, isShort ? 6 : 10)
                }
                
                if geo.size.width >= 640 {
                    // Wide / Split Mode: Balanced Two-Column Stage
                    HStack(spacing: isNarrow ? 14 : max(18, min(36, geo.size.width * 0.03))) {
                        // Left Column: Artwork, Info & Transport (Natural clamped width for the album art)
                        leftStage(geo: geo, isShort: isShort, isNarrow: isNarrow)
                            .frame(width: max(250, min(340, geo.size.width * (isNarrow ? 0.38 : 0.42))))
                        
                        // Right Column: Live Synchronized Lyrics Card (Takes remaining width)
                        rightLyricsStage(isNarrow: isNarrow)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, isNarrow ? 14 : max(18, geo.size.width * 0.03))
                    .padding(.top, isShort ? 6 : 14)
                    .padding(.bottom, isShort ? 8 : 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Compact Mode: Segmented Toggle
                    VStack(spacing: 8) {
                        if viewModel.compactTab == 0 {
                            leftStage(geo: geo, isShort: isShort, isNarrow: isNarrow)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            rightLyricsStage(isNarrow: isNarrow)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .padding(.horizontal, max(16, geo.size.width * 0.03))
                    .padding(.bottom, isShort ? 8 : 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ambientBackground)
    }
    
    // MARK: - Ambient Background
    
    @ViewBuilder
    private var ambientBackground: some View {
        ZStack {
            if isLight {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Color.black
            }
            
            if let artwork = player.currentTrack?.artworkURL {
                AsyncImage(url: artwork) { phase in
                    if case .success(let img) = phase {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: isLight ? 75 : 90)
                            .opacity(isLight ? 0.28 : 0.42)
                    }
                }
            } else {
                LinearGradient(
                    colors: isLight
                        ? [FluidTheme.musicRed.opacity(0.12), Color.purple.opacity(0.08), Color(white: 0.95)]
                        : [FluidTheme.musicRed.opacity(0.25), Color.purple.opacity(0.18), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Subtle overlay to ensure maximum contrast and legibility across themes
            if isLight {
                Color.white.opacity(0.40)
            } else {
                Color.black.opacity(0.35)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    // MARK: - Compact Mode Segmented Picker
    
    @ViewBuilder
    private var compactSegmentedPicker: some View {
        HStack(spacing: 2) {
            Button(action: {
                FluidHaptics.tap()
                withAnimation(FluidTheme.fluidSpring) {
                    viewModel.compactTab = 0
                }
            }) {
                Text("Now Playing")
                    .font(.system(size: 11, weight: viewModel.compactTab == 0 ? .semibold : .medium, design: .rounded))
                    .foregroundColor(viewModel.compactTab == 0 ? (isLight ? .primary : .white) : (isLight ? .secondary : .white.opacity(0.60)))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(
                        viewModel.compactTab == 0
                            ? (isLight ? Color.white : Color.white.opacity(0.22))
                            : Color.clear
                    )
                    .clipShape(Capsule())
                    .shadow(color: viewModel.compactTab == 0 ? Color.black.opacity(isLight ? 0.12 : 0.25) : .clear, radius: 4, x: 0, y: 1)
                    .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                FluidHaptics.tap()
                withAnimation(FluidTheme.fluidSpring) {
                    viewModel.compactTab = 1
                }
            }) {
                Text("Lyrics")
                    .font(.system(size: 11, weight: viewModel.compactTab == 1 ? .semibold : .medium, design: .rounded))
                    .foregroundColor(viewModel.compactTab == 1 ? (isLight ? .primary : .white) : (isLight ? .secondary : .white.opacity(0.60)))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(
                        viewModel.compactTab == 1
                            ? (isLight ? Color.white : Color.white.opacity(0.22))
                            : Color.clear
                    )
                    .clipShape(Capsule())
                    .shadow(color: viewModel.compactTab == 1 ? Color.black.opacity(isLight ? 0.12 : 0.25) : .clear, radius: 4, x: 0, y: 1)
                    .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(3)
        .background(isLight ? Color.black.opacity(0.06) : Color.black.opacity(0.28))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
    
    // MARK: - Left Stage: Hero Album Art & Song Info
    
    @ViewBuilder
    private func leftStage(geo: GeometryProxy, isShort: Bool, isNarrow: Bool = false) -> some View {
        let isCompact = geo.size.width < 760
        let artSize: CGFloat = isNarrow
            ? min(220, min(geo.size.width * 0.34, geo.size.height * (isShort ? 0.38 : 0.44)))
            : (isCompact
                ? min(240, min(geo.size.width * 0.46, geo.size.height * (isShort ? 0.38 : 0.44)))
                : min(320, min(geo.size.width * 0.38, geo.size.height * 0.46)))
        
        VStack(spacing: isShort ? 8 : (isNarrow ? 10 : 14)) {
            Spacer(minLength: 4)
            
            // Hero Album Artwork
            ZStack {
                if let track = player.currentTrack, let art = track.artworkURL {
                    AsyncImage(url: art) { phase in
                        switch phase {
                        case .success(let img):
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            fallbackArt
                        }
                    }
                } else {
                    fallbackArt
                }
            }
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: isNarrow ? 14 : 18, style: .continuous))
            .shadow(color: Color.black.opacity(isLight ? 0.18 : 0.55), radius: isLight ? 14 : 22, x: 0, y: isLight ? 6 : 10)
            .scaleEffect(player.isPlaying ? 1.0 : 0.94)
            .animation(FluidTheme.fluidSpring, value: player.isPlaying)
            
            // Title & Artist Info
            VStack(spacing: 4) {
                if let track = player.currentTrack {
                    Text(track.title)
                        .font(.system(size: isShort ? 16 : (isNarrow ? 18 : 22), weight: .bold, design: .rounded))
                        .foregroundColor(isLight ? .primary : .white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text(track.artist)
                        .font(.system(size: isShort ? 12 : (isNarrow ? 13 : 15), weight: .medium, design: .rounded))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            
            Spacer(minLength: 4)
        }
    }
    
    // MARK: - Right Stage: Live Rolling Synced Lyrics & Static Full-Text View
    
    @ViewBuilder
    private func rightLyricsStage(isNarrow: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: player.isLyricsSynced ? "quote.bubble.fill" : "text.quote")
                        .foregroundColor(player.isLyricsSynced ? FluidTheme.musicRed : (isLight ? .secondary : .white.opacity(0.8)))
                    Text("Lyrics")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isLight ? .primary : .white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    if !player.isLyricsSynced && !player.lyricLines.isEmpty {
                        Text("Full Text")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(isLight ? .secondary : .white.opacity(0.75))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                Spacer(minLength: 6)
                
                if player.isLoadingLyrics {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isLight ? .primary : .white))
                            .scaleEffect(0.65)
                        Text("Syncing...")
                            .font(.system(size: 11))
                            .foregroundColor(isLight ? .secondary : .white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else if !player.lyricLines.isEmpty {
                    lyricsControlPills(isNarrow: isNarrow)
                }
            }
            .padding(.bottom, isNarrow ? 8 : 10)
            
            // Expandable Music DNA Track Story Drawer
            if player.showTrackStory {
                trackStoryCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if player.lyricLines.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.mic")
                        .font(.system(size: 38))
                        .foregroundColor(isLight ? .secondary.opacity(0.4) : .white.opacity(0.3))
                    Text("No lyrics found")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !player.isLyricsSynced {
                // Static / Unsynced Full Text View: Never jumps or scrolls artificially
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(player.lyricLines.enumerated()), id: \.element.id) { index, line in
                            VStack(alignment: .leading, spacing: 3) {
                                if player.showRomanization, let romaji = line.romanization, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(FluidTheme.musicRed.opacity(0.85))
                                }
                                Text(line.text)
                                    .font(.system(size: isNarrow ? 15 : 17, weight: .medium, design: .rounded))
                                    .foregroundColor(isLight ? .primary : .white.opacity(0.92))
                                    .multilineTextAlignment(.leading)
                                if player.showTranslation, let translation = line.translation, !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundColor(isLight ? .secondary : .white.opacity(0.70))
                                        .italic()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, isNarrow ? 16 : 20)
                }
            } else {
                // Synchronized Rolling Karaoke View
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: isNarrow ? 16 : 20) {
                            ForEach(Array(player.lyricLines.enumerated()), id: \.element.id) { index, line in
                                let isCurrent = index == player.activeLyricIndex
                                let isPast = index < player.activeLyricIndex
                                
                                Button(action: {
                                    FluidHaptics.snap()
                                    withAnimation(FluidTheme.fluidSpring) {
                                        player.seekToLyric(at: index)
                                    }
                                }) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        // 1. Romaji / Transliteration (Above Line)
                                        if player.showRomanization, let romaji = line.romanization, !romaji.isEmpty {
                                            Text(romaji)
                                                .font(.system(size: isCurrent ? (isNarrow ? 11 : 12) : (isNarrow ? 9.5 : 10), weight: .medium, design: .rounded))
                                                .foregroundColor(isCurrent ? FluidTheme.musicRed.opacity(0.9) : (isLight ? .secondary.opacity(0.6) : .white.opacity(0.40)))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        
                                        // 2. Main Synchronized Line with Word-by-Word Karaoke Sweep
                                        lyricText(for: line, isCurrent: isCurrent, isPast: isPast, isNarrow: isNarrow)
                                            .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                                            .blur(radius: isCurrent ? 0 : 0.2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // 3. AI Translation Subtitle (Below Line)
                                        if player.showTranslation, let translation = line.translation, !translation.isEmpty {
                                            Text(translation)
                                                .font(.system(size: isCurrent ? (isNarrow ? 12 : 13) : (isNarrow ? 10 : 11), weight: .regular, design: .rounded))
                                                .foregroundColor(isCurrent ? (isLight ? .primary.opacity(0.85) : .white.opacity(0.88)) : (isLight ? .secondary.opacity(0.6) : .white.opacity(0.45)))
                                                .italic()
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.top, 1)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(action: {
                                        player.alignLyric(lineIndex: index)
                                    }) {
                                        Label("Align Lyrics to Current Time (Sync to Now)", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    Button(action: {
                                        player.seekToLyric(at: index)
                                    }) {
                                        Label("Jump to This Line", systemImage: "play.fill")
                                    }
                                }
                                .id(line.id)
                            }
                        }
                        .padding(.vertical, isNarrow ? 20 : 30)
                    }
                    .onChange(of: player.activeLyricIndex) { _, newIndex in
                        if newIndex >= 0 && newIndex < player.lyricLines.count {
                            withAnimation(.easeInOut(duration: 0.45)) {
                                proxy.scrollTo(player.lyricLines[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(isNarrow ? 14 : 16)
        .background(isLight ? Color.white.opacity(0.55) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: isLight ? Color.black.opacity(0.05) : Color.clear, radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Word-by-Word Karaoke Attributed Text Sweep
    
    @ViewBuilder
    private func lyricText(for line: LyricLine, isCurrent: Bool, isPast: Bool, isNarrow: Bool = false) -> some View {
        let currentSize: CGFloat = isNarrow ? 20 : 24
        let pastSize: CGFloat = isNarrow ? 15 : 18
        if isCurrent && !line.words.isEmpty {
            let attr: AttributedString = {
                var res = AttributedString()
                for (wIdx, word) in line.words.enumerated() {
                    var wordAttr = AttributedString(word.word + (wIdx < line.words.count - 1 ? " " : ""))
                    if wIdx < player.activeWordIndex {
                        wordAttr.foregroundColor = isLight ? .primary : .white
                        wordAttr.font = .system(size: currentSize, weight: .bold, design: .rounded)
                    } else if wIdx == player.activeWordIndex {
                        wordAttr.foregroundColor = FluidTheme.musicRed
                        wordAttr.font = .system(size: currentSize + 1, weight: .heavy, design: .rounded)
                    } else {
                        wordAttr.foregroundColor = isLight ? Color.primary.opacity(0.45) : Color.white.opacity(0.50)
                        wordAttr.font = .system(size: currentSize, weight: .bold, design: .rounded)
                    }
                    res.append(wordAttr)
                }
                return res
            }()
            Text(attr)
                .multilineTextAlignment(.leading)
        } else {
            Text(line.text)
                .font(.system(size: isCurrent ? currentSize : pastSize, weight: isCurrent ? .bold : .medium, design: .rounded))
                .foregroundColor(isCurrent ? (isLight ? .primary : .white) : (isPast ? (isLight ? .secondary.opacity(0.45) : .white.opacity(0.35)) : (isLight ? .secondary : .white.opacity(0.6))))
                .multilineTextAlignment(.leading)
        }
    }
    
    // MARK: - Lyrics Control Capsules (Romaji, Translate, Story & Sync)
    
    @ViewBuilder
    private func lyricsControlPills(isNarrow: Bool = false) -> some View {
        HStack(spacing: 3) {
            // Romaji / Transliteration Toggle
            Button(action: {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleRomanization()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "character.phonetic")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Romaji")
                        .font(.system(size: 10.5, weight: player.showRomanization ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showRomanization ? .white : (isLight ? .primary.opacity(0.75) : .white.opacity(0.75)))
                .padding(.horizontal, isNarrow ? 7 : 9)
                .frame(height: 25)
                .background(player.showRomanization ? FluidTheme.musicRed : (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .help("Toggle phonetic romanization for Japanese, Chinese, Hindi & world scripts")
            
            // AI Translation Toggle
            Button(action: {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleTranslation()
                }
            }) {
                HStack(spacing: 4) {
                    if player.isTranslatingLyrics {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isLight ? .primary : .white))
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    Text("Translate")
                        .font(.system(size: 10.5, weight: player.showTranslation ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showTranslation ? .white : (isLight ? .primary.opacity(0.75) : .white.opacity(0.75)))
                .padding(.horizontal, isNarrow ? 7 : 9)
                .frame(height: 25)
                .background(player.showTranslation ? FluidTheme.musicRed : (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .help("Translate lyrics line-by-line into English")
            
            // Music DNA Song Story Toggle
            Button(action: {
                withAnimation(FluidTheme.fluidSpring) {
                    player.toggleTrackStory()
                }
            }) {
                HStack(spacing: 4) {
                    if player.isLoadingStory {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isLight ? .primary : .white))
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    Text("Story")
                        .font(.system(size: 10.5, weight: player.showTrackStory ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showTrackStory ? .white : (isLight ? .primary.opacity(0.75) : .white.opacity(0.75)))
                .padding(.horizontal, isNarrow ? 7 : 9)
                .frame(height: 25)
                .background(player.showTrackStory ? FluidTheme.musicRed : (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .help("View Song Meaning & Wikipedia Track DNA")
            
            // Sync Calibration Offset Pill
            lyricSyncPill(isNarrow: isNarrow)
        }
        .padding(2.5)
        .background(isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
    
    // MARK: - Music DNA Song Story Card
    
    @ViewBuilder
    private var trackStoryCard: some View {
        if let story = player.trackStory {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.yellow)
                    Text("Track Story & Meaning")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isLight ? .primary : .white)
                    
                    if let genre = story.genre {
                        Text(genre)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(isLight ? FluidTheme.musicRed : .white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isLight ? FluidTheme.musicRed.opacity(0.12) : FluidTheme.musicRed.opacity(0.35))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    if let year = story.releaseYear {
                        Text(year)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(isLight ? .secondary : .white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    
                    Button(action: {
                        withAnimation(FluidTheme.fluidSpring) {
                            player.showTrackStory = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(isLight ? .secondary : .white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                let rawText = story.extract.isEmpty ? story.summary : story.extract
                let cleanText = rawText.replacingOccurrences(of: "..", with: ".")
                Text(cleanText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(isLight ? .primary.opacity(0.9) : .white.opacity(0.92))
                    .lineSpacing(3)
                    .lineLimit(5)
                
                HStack {
                    Text("Source: \(story.source)")
                        .font(.system(size: 9))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.45))
                    Spacer()
                }
            }
            .padding(11)
            .background(isLight ? FluidTheme.musicRed.opacity(0.06) : FluidTheme.musicRed.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isLight ? FluidTheme.musicRed.opacity(0.20) : FluidTheme.musicRed.opacity(0.35), lineWidth: 0.5)
            )
            .padding(.bottom, 8)
        } else if player.isLoadingStory {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isLight ? .primary : .white))
                    .scaleEffect(0.6)
                Text("Analyzing Music DNA & Story...")
                    .font(.system(size: 11))
                    .foregroundColor(isLight ? .secondary : .white.opacity(0.65))
                Spacer()
            }
            .padding(8)
            .background(isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private func lyricSyncPill(isNarrow: Bool = false) -> some View {
        if player.isLyricsSynced {
            Button(action: {
                player.showSyncCalibrationPopover.toggle()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(player.userLyricOffset == 0 ? "Sync" : String(format: "%+.1fs", player.userLyricOffset))
                        .font(.system(size: 10.5, weight: player.userLyricOffset != 0 ? .semibold : .medium, design: player.userLyricOffset == 0 ? .rounded : .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(player.userLyricOffset != 0 ? .white : (isLight ? .primary.opacity(0.75) : .white.opacity(0.75)))
                .padding(.horizontal, isNarrow ? 7 : 9)
                .frame(height: 25)
                .background(
                    player.userLyricOffset != 0
                        ? FluidTheme.musicRed
                        : (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .popover(isPresented: $player.showSyncCalibrationPopover, arrowEdge: .bottom) {
                syncCalibrationPopoverContent
            }
            .help("Click to calibrate or fine-tune lyrics synchronization")
        }
    }
    
    @ViewBuilder
    private var syncCalibrationPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.2.square")
                    .foregroundColor(FluidTheme.musicRed)
                Text("Lyrics Sync Calibration")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button("Reset (0.0s)") {
                    player.resetLyricOffset()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(FluidTheme.musicRed)
            }
            
            // One-Tap Instant Alignment
            Button(action: {
                player.alignLyric(lineIndex: player.activeLyricIndex)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                    Text("⚡ Align Active Line to Now")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(FluidTheme.musicRed)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Instantly aligns lyrics so the active line matches what you hear right now")
            
            Divider()
            
            // Nudge Buttons
            HStack(spacing: 6) {
                Text("Nudge:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("-0.5s") { player.adjustLyricOffset(by: -0.5) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("-0.1s") { player.adjustLyricOffset(by: -0.1) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("+0.1s") { player.adjustLyricOffset(by: 0.1) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("+0.5s") { player.adjustLyricOffset(by: 0.5) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            
            HStack {
                Text("Current Offset:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%+.2fs", player.userLyricOffset))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(player.userLyricOffset != 0 ? FluidTheme.musicRed : .primary)
            }
        }
        .padding(14)
        .frame(width: 290)
    }
    
    private var fallbackArt: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 54))
                    .foregroundColor(isLight ? .secondary.opacity(0.4) : .white.opacity(0.4))
            )
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}
