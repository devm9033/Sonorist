import SwiftUI

/// Sheet modal showing live synchronized lyrics with tap-to-seek support
public struct LyricsView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(player.isLyricsSynced ? FluidTheme.musicRed : Color.secondary)
                            .frame(width: 22, height: 22)
                        Image(systemName: player.isLyricsSynced ? "quote.bubble.fill" : "text.quote")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Lyrics")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    
                    if !player.isLyricsSynced && !player.lyricLines.isEmpty {
                        Text("Full Text")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                if !player.lyricLines.isEmpty {
                    lyricsControlPills
                }
                
                Button(action: {
                    FluidHaptics.tap()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close Lyrics (Esc)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Expandable Music DNA Track Story Drawer
            if player.showTrackStory {
                trackStoryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if player.isLoadingLyrics {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView("Fetching lyrics from LRCLIB & NetEase...")
                        .font(FluidTheme.captionFont)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if player.lyricLines.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.mic")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No synchronized lyrics found")
                        .font(FluidTheme.headlineFont)
                        .foregroundColor(.secondary)
                    Text("Lyrics will automatically display when available for the active track.")
                        .font(FluidTheme.captionFont)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    if let track = player.currentTrack {
                        Button(action: {
                            Task {
                                await player.loadLyrics(for: track)
                            }
                        }) {
                            Label("Retry Lyrics Sync", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FluidTheme.musicRed)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 6)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !player.isLyricsSynced {
                // Static / Unsynced Full Text View: Clean, scrollable without fake timers
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(player.lyricLines.enumerated()), id: \.element.id) { index, line in
                            VStack(alignment: .leading, spacing: 3) {
                                if player.showRomanization, let romaji = line.romanization, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(FluidTheme.musicRed.opacity(0.85))
                                }
                                Text(line.text)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.88))
                                    .multilineTextAlignment(.leading)
                                if player.showTranslation, let translation = line.translation, !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(24)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(player.lyricLines.enumerated()), id: \.element.id) { index, line in
                                let isCurrent = index == player.activeLyricIndex
                                let isPast = index < player.activeLyricIndex
                                
                                Button(action: {
                                    withAnimation(FluidTheme.fluidSpring) {
                                        player.seekToLyric(at: index)
                                    }
                                }) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        // 1. Romaji / Transliteration (Above Line)
                                        if player.showRomanization, let romaji = line.romanization, !romaji.isEmpty {
                                            Text(romaji)
                                                .font(.system(size: isCurrent ? 12 : 10, weight: .medium, design: .rounded))
                                                .foregroundColor(isCurrent ? FluidTheme.musicRed.opacity(0.85) : .secondary.opacity(0.55))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        
                                        // 2. Main Synchronized Line with Word-by-Word Karaoke Sweep
                                        lyricText(for: line, isCurrent: isCurrent, isPast: isPast)
                                            .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                                            .blur(radius: isCurrent ? 0 : 0.2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // 3. AI Translation Subtitle (Below Line)
                                        if player.showTranslation, let translation = line.translation, !translation.isEmpty {
                                            Text(translation)
                                                .font(.system(size: isCurrent ? 13 : 11, weight: .regular, design: .rounded))
                                                .foregroundColor(isCurrent ? .primary.opacity(0.85) : .secondary.opacity(0.65))
                                                .italic()
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.top, 1)
                                        }
                                    }
                                    .padding(.vertical, 2)
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
                        .padding(24)
                    }
                    .onChange(of: player.activeLyricIndex) { _, newIndex in
                        if newIndex >= 0 && newIndex < player.lyricLines.count {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(player.lyricLines[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 540, height: 640)
        .background(FluidTheme.barMaterial)
    }
    
    // MARK: - Word-by-Word Karaoke Attributed Text Sweep
    
    @ViewBuilder
    private func lyricText(for line: LyricLine, isCurrent: Bool, isPast: Bool) -> some View {
        if isCurrent && !line.words.isEmpty {
            let attr: AttributedString = {
                var res = AttributedString()
                for (wIdx, word) in line.words.enumerated() {
                    var wordAttr = AttributedString(word.word + (wIdx < line.words.count - 1 ? " " : ""))
                    if wIdx < player.activeWordIndex {
                        wordAttr.foregroundColor = .primary
                        wordAttr.font = .system(size: 22, weight: .bold, design: .rounded)
                    } else if wIdx == player.activeWordIndex {
                        wordAttr.foregroundColor = FluidTheme.musicRed
                        wordAttr.font = .system(size: 23, weight: .heavy, design: .rounded)
                    } else {
                        wordAttr.foregroundColor = .primary.opacity(0.50)
                        wordAttr.font = .system(size: 22, weight: .bold, design: .rounded)
                    }
                    res.append(wordAttr)
                }
                return res
            }()
            Text(attr)
                .multilineTextAlignment(.leading)
        } else {
            Text(line.text)
                .font(.system(size: isCurrent ? 22 : 17, weight: isCurrent ? .bold : .medium, design: .rounded))
                .foregroundColor(isCurrent ? FluidTheme.musicRed : (isPast ? .secondary.opacity(0.6) : .primary.opacity(0.85)))
                .multilineTextAlignment(.leading)
        }
    }
    
    // MARK: - Header Capsules (Romaji, Translate, Story & Sync)
    
    @ViewBuilder
    private var lyricsControlPills: some View {
        HStack(spacing: 4) {
            // Romaji Toggle
            Button(action: {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleRomanization()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "character.phonetic")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Romaji")
                        .font(.system(size: 11, weight: player.showRomanization ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showRomanization ? .white : .primary.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(player.showRomanization ? FluidTheme.musicRed : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .help("Toggle phonetic romanization")
            
            // AI Translation Toggle
            Button(action: {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleTranslation()
                }
            }) {
                HStack(spacing: 5) {
                    if player.isTranslatingLyrics {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Translate")
                        .font(.system(size: 11, weight: player.showTranslation ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showTranslation ? .white : .primary.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(player.showTranslation ? FluidTheme.musicRed : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                HStack(spacing: 5) {
                    if player.isLoadingStory {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Story")
                        .font(.system(size: 11, weight: player.showTrackStory ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(player.showTrackStory ? .white : .primary.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(player.showTrackStory ? FluidTheme.musicRed : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .help("View Song Meaning & Wikipedia Track DNA")
            
            // Sync Offset Adjuster
            lyricSyncPill
        }
        .padding(3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
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
                    
                    if let genre = story.genre {
                        Text(genre)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    if let year = story.releaseYear {
                        Text(year)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    Button(action: {
                        withAnimation(FluidTheme.fluidSpring) {
                            player.showTrackStory = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Text(story.extract.isEmpty ? story.summary : story.extract)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(0.88))
                    .lineSpacing(2)
                    .lineLimit(5)
                
                HStack {
                    Text("Source: \(story.source)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
            }
            .padding(10)
            .background(Color.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
            )
        } else if player.isLoadingStory {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.6)
                Text("Analyzing Music DNA & Story...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    @ViewBuilder
    private var lyricSyncPill: some View {
        if player.isLyricsSynced {
            Button(action: {
                player.showSyncCalibrationPopover.toggle()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text(player.userLyricOffset == 0 ? "Sync" : String(format: "%+.1fs", player.userLyricOffset))
                        .font(.system(size: 11, weight: player.userLyricOffset != 0 ? .semibold : .medium, design: player.userLyricOffset == 0 ? .rounded : .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(player.userLyricOffset != 0 ? .white : .primary.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    player.userLyricOffset != 0
                        ? FluidTheme.musicRed
                        : Color.secondary.opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("-0.1s") { player.adjustLyricOffset(by: -0.1) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("+0.1s") { player.adjustLyricOffset(by: 0.1) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button("+0.5s") { player.adjustLyricOffset(by: 0.5) }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
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
}
