import SwiftUI

@MainActor
public final class PlayerBarViewModel: ObservableObject {
    public static let shared = PlayerBarViewModel()
    @Published public var showAudioQualityPopover: Bool = false
    @Published public var showSleepTimerPopover: Bool = false
    public init() {}
}

public struct PlayerBarView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var barModel = PlayerBarViewModel.shared
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Interactive background: Clicking empty/neutral bar space toggles (maximizes / minimizes) Now Playing
            Rectangle()
                .fill(FluidTheme.barMaterial)
                .contentShape(Rectangle())
                .onTapGesture {
                    FluidHaptics.toggle()
                    withAnimation(FluidTheme.fluidSpring) {
                        player.isImmersiveViewActive.toggle()
                    }
                }
                .help(player.isImmersiveViewActive ? "Click bar to minimize Now Playing (⌘F or Esc)" : "Click bar to maximize Now Playing (⌘F)")
            
            // Foreground Layer: Interactive controls, scrubber & transport
            GeometryReader { barGeo in
                let isCompact = barGeo.size.width < 900
                let isVeryNarrow = barGeo.size.width < 620
                
                VStack(spacing: 5) {
                    // Optional Error Banner
                    if let err = player.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 10))
                            Text(err)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button("Dismiss") {
                                player.errorMessage = nil
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, isCompact ? 14 : 20)
                    }
                    
                    // Top Scrubber Progress Line (Isolated subview to decouple 250ms playback ticks from the rest of PlayerBar)
                    PlayerBarScrubberLine(isCompact: isCompact)
                    
                    // Bottom Main Control Bar with true 3-column non-overlapping layout (100% centered, 0% overlap)
                    HStack(spacing: isCompact ? 18 : 24) {
                        // Leading Column: Track Info & Like Button (aligned leading)
                        leftTrackInfo(isCompact: isCompact, isVeryNarrow: isVeryNarrow)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        
                        // Center Column: Playback Transport Buttons (Strictly centered, protected priority)
                        centerTransport(isCompact: isCompact, isVeryNarrow: isVeryNarrow)
                            .layoutPriority(2)
                        
                        // Trailing Column: Accessories & Volume Controls (aligned trailing)
                        rightControls(isCompact: isCompact, isVeryNarrow: isVeryNarrow)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, isCompact ? 14 : 20)
                    .padding(.bottom, 8)
                }
                .frame(width: barGeo.size.width, height: 80)
            }
        }
        .frame(minHeight: 80, idealHeight: 80, maxHeight: 80)
    }
    
// MARK: - Scrubber Line (Isolated Subview)

public struct PlayerBarScrubberLine: View {
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    let isCompact: Bool
    
    public init(isCompact: Bool) {
        self.isCompact = isCompact
    }
    
    public var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Text(formatTime(player.isDraggingScrubber ? player.dragScrubTime : progressTracker.currentTime))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 3)
                    
                    // Progress fill
                    let progress = player.duration > 0 ? (player.isDraggingScrubber ? player.dragScrubTime : progressTracker.currentTime) / player.duration : 0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [FluidTheme.musicRed, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 3)
                    
                    // Scrubber thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(geo.size.width * CGFloat(progress) - 5, geo.size.width - 10)))
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            player.isDraggingScrubber = true
                            let ratio = max(0, min(value.location.x / geo.size.width, 1.0))
                            player.dragScrubTime = ratio * player.duration
                        }
                        .onEnded { value in
                            let ratio = max(0, min(value.location.x / geo.size.width, 1.0))
                            let targetTime = ratio * player.duration
                            player.seek(to: targetTime)
                            player.isDraggingScrubber = false
                        }
                )
            }
            .frame(height: 16)
            
            Text(formatTime(player.duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .leading)
        }
        .padding(.horizontal, isCompact ? 14 : 20)
        .padding(.top, 4)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
    
    // MARK: - Left Track Info
    
    @ViewBuilder
    private func leftTrackInfo(isCompact: Bool, isVeryNarrow: Bool) -> some View {
        let artDim: CGFloat = isVeryNarrow ? 34 : (isCompact ? 38 : 44)
        let textMaxWidth: CGFloat = isVeryNarrow ? 110 : (isCompact ? 135 : 210)
        
        HStack(spacing: isVeryNarrow ? 6 : (isCompact ? 8 : 10)) {
            if let track = player.currentTrack {
                Button(action: {
                    FluidHaptics.toggle()
                    withAnimation(FluidTheme.fluidSpring) {
                        player.isImmersiveViewActive.toggle()
                    }
                }) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.gray.opacity(0.3)
                                .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
                        }
                    }
                    .frame(width: artDim, height: artDim)
                    .clipShape(RoundedRectangle(cornerRadius: isVeryNarrow ? 6 : (isCompact ? 7 : 8), style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: isVeryNarrow ? 6 : (isCompact ? 7 : 8), style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: isVeryNarrow ? 6 : (isCompact ? 7 : 8), style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .help(player.isImmersiveViewActive ? "Minimize to Standard View (⌘F)" : "Open Full-Window Now Playing (⌘F)")
                
                // Track metadata (hugs text tightly without empty gaps)
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: {
                        FluidHaptics.toggle()
                        withAnimation(FluidTheme.fluidSpring) {
                            player.isImmersiveViewActive.toggle()
                        }
                    }) {
                        Text(track.title)
                            .font(.system(size: isVeryNarrow ? 11 : (isCompact ? 12 : 13), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: textMaxWidth, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(player.isImmersiveViewActive ? "Minimize to Standard View (⌘F)" : "Open Full-Window Now Playing (⌘F)")
                    
                    HStack(spacing: 5) {
                        Text(track.artist)
                            .font(.system(size: isVeryNarrow ? 10 : (isCompact ? 10.5 : 11), weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: max(45, textMaxWidth - 40), alignment: .leading)
                        
                        // Audio Quality Selector Badge (Clean Pill Button with Popover)
                        Button(action: {
                            FluidHaptics.tap()
                            barModel.showAudioQualityPopover.toggle()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 8, weight: .bold))
                                Text(player.selectedAudioQuality.shortLabel)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(barModel.showAudioQualityPopover ? FluidTheme.musicRed.opacity(0.3) : FluidTheme.musicRed.opacity(0.15))
                            .foregroundColor(FluidTheme.musicRed)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(FluidTheme.musicRed.opacity(0.3), lineWidth: 0.5)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Audio Stream Quality & Format")
                        .popover(isPresented: $barModel.showAudioQualityPopover, arrowEdge: .top) {
                            audioQualityPopoverContent
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                
                // Favorite / Like Heart Button: Directly adjacent to text block with comfortable touch target
                Button(action: {
                    FluidHaptics.toggle()
                    withAnimation(FluidTheme.tapSpring) {
                        player.toggleLike(track: track)
                    }
                }) {
                    Image(systemName: player.isLiked(track: track) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(player.isLiked(track: track) ? FluidTheme.musicRed : .secondary.opacity(0.65))
                }
                .buttonStyle(ApplePlayerButtonStyle(width: 26, height: 26, cornerRadius: 6))
                .help(player.isLiked(track: track) ? "Unlike Song" : "Like Song")
            } else {
                Button(action: {
                    FluidHaptics.toggle()
                    withAnimation(FluidTheme.fluidSpring) {
                        player.isImmersiveViewActive.toggle()
                    }
                }) {
                    HStack(spacing: isVeryNarrow ? 6 : (isCompact ? 8 : 10)) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: artDim, height: artDim)
                            .overlay(Image(systemName: "music.quarternote.3").foregroundColor(.secondary))
                        
                        Text("Ready to play")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Center Transport
    
    @ViewBuilder
    private func centerTransport(isCompact: Bool, isVeryNarrow: Bool) -> some View {
        let btnDim: CGFloat = isVeryNarrow ? 26 : (isCompact ? 28 : 32)
        let playDim: CGFloat = isVeryNarrow ? 34 : (isCompact ? 36 : 42)
        let iconSize: CGFloat = isVeryNarrow ? 11 : (isCompact ? 12 : 14)
        let playIconSize: CGFloat = isVeryNarrow ? 14 : (isCompact ? 15 : 17)
        let spacing: CGFloat = isVeryNarrow ? 5 : (isCompact ? 8 : 12)
        
        HStack(spacing: spacing) {
            // Shuffle (Hidden when very narrow to prioritize core playback)
            if !isVeryNarrow {
                Button(action: {
                    FluidHaptics.tap()
                    withAnimation(FluidTheme.tapSpring) {
                        player.isShuffle.toggle()
                    }
                }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(player.isShuffle ? FluidTheme.musicRed : .secondary)
                }
                .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
                .help(player.isShuffle ? "Shuffle On" : "Shuffle Off")
            }
            
            // Previous Track
            Button(action: {
                FluidHaptics.tap()
                player.previous()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: isCompact ? 13 : 15))
                    .foregroundColor(.primary)
            }
            .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
            .help("Previous Track (⌘←)")
            
            // Play / Pause / Buffering Button (Circular with full-circle hit target)
            Button(action: {
                FluidHaptics.toggle()
                player.togglePlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(FluidTheme.musicRed)
                        .frame(width: playDim, height: playDim)
                        .shadow(color: FluidTheme.musicRed.opacity(0.35), radius: 6, x: 0, y: 3)
                    
                    if player.isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playIconSize, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(TactileButtonStyle(scaleAmount: 0.92))
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
            
            // Next Track
            Button(action: {
                FluidHaptics.tap()
                player.next()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: isCompact ? 13 : 15))
                    .foregroundColor(.primary)
            }
            .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
            .help("Next Track (⌘→)")
            
            // Repeat (Hidden when very narrow to prioritize core playback)
            if !isVeryNarrow {
                Button(action: {
                    FluidHaptics.tap()
                    withAnimation(FluidTheme.tapSpring) {
                        player.isRepeat.toggle()
                    }
                }) {
                    Image(systemName: "repeat")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(player.isRepeat ? FluidTheme.musicRed : .secondary)
                }
                .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
                .help(player.isRepeat ? "Repeat On" : "Repeat Off")
            }
        }
        .layoutPriority(2)
    }
    
    // MARK: - Right Controls
    
    @ViewBuilder
    private func rightControls(isCompact: Bool, isVeryNarrow: Bool) -> some View {
        let btnDim: CGFloat = isVeryNarrow ? 26 : (isCompact ? 28 : 30)
        let spacing: CGFloat = isVeryNarrow ? 4 : (isCompact ? 6 : 10)
        let sliderWidth: CGFloat = isCompact ? 52 : 72
        
        HStack(spacing: spacing) {
            // Synced Lyrics Button:
            // Displayed in standard views (Search, Library, Analytics) so the user can open the lyrics sheet.
            // Omitted in Now Playing mode as live synchronized lyrics are already displayed full-screen.
            if !player.isImmersiveViewActive {
                Button(action: {
                    FluidHaptics.tap()
                    player.showLyricsSheet = true
                }) {
                    Image(systemName: player.showLyricsSheet ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                        .foregroundColor(player.showLyricsSheet ? FluidTheme.musicRed : .secondary)
                }
                .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
                .help("View Live Synced Lyrics (⌘L)")
            }
            
            // Up Next Queue Button
            Button(action: {
                FluidHaptics.tap()
                player.showQueueSheet = true
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                    .foregroundColor(player.showQueueSheet ? FluidTheme.musicRed : .secondary)
            }
            .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
            .help("Up Next Queue (⌘U)")
            
            // Full-Window Immersive View Toggle Button
            Button(action: {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.fluidSpring) {
                    player.isImmersiveViewActive.toggle()
                }
            }) {
                Image(systemName: player.isImmersiveViewActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundColor(player.isImmersiveViewActive ? FluidTheme.musicRed : .secondary)
            }
            .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
            .help(player.isImmersiveViewActive ? "Exit Now Playing (⌘F or Esc)" : "Open Full-Window Now Playing (⌘F)")
            
            // Direct Sleep Timer Button (Clean Apple-style icon with NO disclosure arrow)
            Button(action: {
                FluidHaptics.tap()
                barModel.showSleepTimerPopover.toggle()
            }) {
                Image(systemName: player.sleepTimerRemainingSeconds > 0 ? "moon.fill" : "moon")
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                    .foregroundColor(player.sleepTimerRemainingSeconds > 0 ? FluidTheme.musicRed : (barModel.showSleepTimerPopover ? FluidTheme.musicRed : .secondary))
            }
            .buttonStyle(ApplePlayerButtonStyle(width: btnDim, height: btnDim, cornerRadius: 6))
            .help(player.sleepTimerRemainingSeconds > 0 ? "Sleep Timer: \(player.formattedSleepTimerRemaining)" : "Set Sleep Timer")
            .popover(isPresented: $barModel.showSleepTimerPopover, arrowEdge: .top) {
                sleepTimerPopoverContent
            }
            
            // Volume Control
            HStack(spacing: 4) {
                Button(action: {
                    FluidHaptics.tap()
                    if player.volume > 0 {
                        player.preMuteVolume = player.volume
                        player.volume = 0
                    } else {
                        player.volume = player.preMuteVolume > 0 ? player.preMuteVolume : 0.8
                    }
                }) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: isCompact ? 11 : 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(ApplePlayerButtonStyle(width: isCompact ? 24 : 26, height: isCompact ? 24 : 26, cornerRadius: 5))
                .help(player.volume == 0 ? "Unmute" : "Mute")
                
                if !isVeryNarrow {
                    Slider(value: Binding(
                        get: { Double(player.volume) },
                        set: { player.volume = Float($0) }
                    ), in: 0...1)
                    .frame(width: sliderWidth)
                    .accentColor(FluidTheme.musicRed)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var volumeIcon: String {
        if player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.33 { return "speaker.wave.1.fill" }
        if player.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
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
    
    // MARK: - Sleep Timer Popover Card
    
    @ViewBuilder
    private var sleepTimerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Sleep Timer")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                if player.sleepTimerRemainingSeconds > 0 {
                    Text(player.formattedSleepTimerRemaining)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(FluidTheme.musicRed)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            
            Divider()
                .opacity(0.3)
            
            ForEach(SleepTimerOption.allCases) { opt in
                sleepTimerRow(opt: opt)
            }
        }
        .padding(4)
        .frame(width: 175)
    }
    
    @ViewBuilder
    private func sleepTimerRow(opt: SleepTimerOption) -> some View {
        let isSelected = player.sleepTimerOption == opt
        Button(action: {
            FluidHaptics.toggle()
            player.setSleepTimer(opt)
            barModel.showSleepTimerPopover = false
        }) {
            HStack {
                Text(opt.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePopoverRowStyle(isSelected: isSelected))
    }
    
    // MARK: - Audio Quality Popover Card
    
    @ViewBuilder
    private var audioQualityPopoverContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundColor(FluidTheme.musicRed)
                    .font(.system(size: 11, weight: .bold))
                Text("Audio Quality")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(player.selectedAudioQuality.shortLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(FluidTheme.musicRed)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FluidTheme.musicRed.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            
            Divider()
                .opacity(0.3)
            
            ForEach(AudioQuality.allCases) { q in
                audioQualityRow(q: q)
            }
        }
        .padding(4)
        .frame(width: 195)
    }
    
    @ViewBuilder
    private func audioQualityRow(q: AudioQuality) -> some View {
        let isSelected = player.selectedAudioQuality == q
        Button(action: {
            FluidHaptics.toggle()
            player.switchQuality(to: q)
            barModel.showAudioQualityPopover = false
        }) {
            HStack {
                Text(q.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePopoverRowStyle(isSelected: isSelected))
    }
}
