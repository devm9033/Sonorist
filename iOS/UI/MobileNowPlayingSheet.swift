import SwiftUI

public final class MobileNowPlayingSheetModel: ObservableObject {
    public static let shared = MobileNowPlayingSheetModel()

    @Published public var showLyrics: Bool = false
    @Published public var dragOffset: CGFloat = 0

    // Artwork Horizontal Slide & Fade Transition State
    @Published public var isTransitioningArtwork: Bool = false
    @Published public var transitionOutgoingTrack: Track? = nil
    @Published public var transitionIncomingTrack: Track? = nil
    @Published public var transitionDirection: PlaybackSlideDirection = .forward
    @Published public var transitionProgress: CGFloat = 0.0
    @Published public var artworkDragOffset: CGFloat = 0
    @Published public var isDraggingArtwork: Bool = false

    @Published public var isSeeking: Bool = false
    @Published public var seekPosition: Double = 0
    @Published public var showQueueSheet: Bool = false
    @Published public var showSleepTimerSheet: Bool = false
    @Published public var showEqualizerSheet: Bool = false

    public init() {}
}

/// Full-screen iOS Now Playing modal sheet.
/// Matches Apple Music iOS design with synchronized karaoke lyrics, fluid gesture dismissal,
/// ambient album artwork mesh illumination, and transport controls.
public struct MobileNowPlayingSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var model = MobileNowPlayingSheetModel.shared
    @ObservedObject private var audioSession = iOSAudioSessionManager.shared
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { rootGeo in
            let screenWidth = rootGeo.size.width
            let screenHeight = rootGeo.size.height
            let contentWidth = max(280, screenWidth - 48)
            let topBarWidth = max(280, screenWidth - 32)

            // Safe top inset to ensure grabber and header sit fully clear of Dynamic Island
            let safeTop: CGFloat = {
                #if os(iOS)
                if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                    return max(59, window.safeAreaInsets.top)
                }
                #endif
                return max(59, rootGeo.safeAreaInsets.top)
            }()
            let topSafePadding = safeTop + 8

            ZStack {
                // Ambient Backdrop Derived from Artwork
                ambientBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Apple Music Centered Grabber Bar (Safely below Dynamic Island)
                    grabberHandle
                        .padding(.top, topSafePadding)
                        .padding(.bottom, 6)

                    // Centered Header & Actions (Equatable - completely isolated from playback re-render thrashing)
                    NowPlayingHeaderRow(
                        width: topBarWidth,
                        isOffline: player.isPlayingFromOfflineLibrary || player.currentTrack?.isCached == true || MediaCacheManager.shared.isCached(videoId: player.currentTrack?.id ?? ""),
                        albumTitle: {
                            if player.isPlayingFromOfflineLibrary {
                                return "Offline Library"
                            }
                            if player.currentTrack?.isCached == true || MediaCacheManager.shared.isCached(videoId: player.currentTrack?.id ?? "") {
                                return "Offline Download"
                            }
                            let raw = (player.currentTrack?.album ?? "").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).union(.symbols))
                            if raw.count < 2 || raw.lowercased() == "youtube music" {
                                return "YouTube Music Queue"
                            }
                            return raw
                        }(),
                        currentTrack: player.currentTrack
                    )
                    .equatable()
                    .padding(.bottom, 10)

                    // Auxiliary Lyrics & Story Pills (visible when lyrics mode is active)
                    if model.showLyrics {
                        lyricsAuxiliaryBar(width: contentWidth)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Music DNA Track Story Drawer
                    if model.showLyrics && player.showTrackStory {
                        trackStoryDrawer(width: contentWidth)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    let artworkSize = min(contentWidth - 24, max(220, screenHeight * 0.35))

                    // Flexible Middle Stage: Artwork or Scrolling Lyrics (Smooth cross-fade, zero layout thrashing)
                    ZStack {
                        largeArtworkView(size: artworkSize)
                            .opacity(model.showLyrics ? 0 : 1)
                            .scaleEffect(model.showLyrics ? 0.92 : 1.0)
                            .allowsHitTesting(!model.showLyrics)

                        scrollingLyricsView(width: contentWidth)
                            .opacity(model.showLyrics ? 1 : 0)
                            .allowsHitTesting(model.showLyrics)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer(minLength: 4)

                    // Track Metadata & Favorite Heart
                    metadataRow(width: contentWidth)
                        .padding(.bottom, 12)

                    // Scrubber & Timestamps (Isolated from parent view updates)
                    NowPlayingScrubberSection(width: contentWidth)
                        .padding(.bottom, 14)

                    // Transport Playback Controls
                    transportControls(width: contentWidth, artworkSize: artworkSize)
                        .padding(.bottom, 14)

                    // Bottom Accessories: Lyrics Toggle, Audio Route, Queue
                    bottomAccessoryBar(width: contentWidth)
                        .padding(.bottom, 34)
                }
                .frame(width: screenWidth)
            }
            .frame(width: screenWidth, height: screenHeight)
            .contentShape(Rectangle())
            .offset(y: max(0, model.dragOffset))
            // Interactive downward pull-to-dismiss gesture for the sheet
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) * 1.5 && !model.showLyrics {
                            model.dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        guard !model.showLyrics else { return }
                        if value.translation.height > 90 || value.predictedEndTranslation.height > 160 {
                            MobileHaptics.trigger(.medium)
                            withAnimation(FluidTheme.fluidSpring) {
                                isPresented = false
                                model.dragOffset = 0
                            }
                        } else {
                            withAnimation(FluidTheme.fluidSpring) {
                                model.dragOffset = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .sheet(isPresented: $model.showQueueSheet) {
            MobileQueueSheet()
                .preferredColorScheme(AppThemeManager.shared.currentTheme.colorScheme)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $model.showSleepTimerSheet) {
            MobileSleepTimerSheet()
                .preferredColorScheme(AppThemeManager.shared.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $model.showEqualizerSheet) {
            MobileEqualizerSheet()
                .preferredColorScheme(AppThemeManager.shared.currentTheme.colorScheme)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    // MARK: - Ambient Backdrop

    private var ambientBackground: some View {
        AmbientArtworkBackdrop(artworkURL: player.currentTrack?.artworkURL, colorScheme: colorScheme)
            .equatable()
    }

    // MARK: - Top Grabber Handle & Header

    private var grabberHandle: some View {
        Button {
            MobileHaptics.trigger(.light)
            withAnimation(FluidTheme.fluidSpring) {
                isPresented = false
            }
        } label: {
            Capsule()
                .fill(colorScheme == .light ? Color.primary.opacity(0.2) : Color.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Dismiss Now Playing")
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if value.translation.height > 0 {
                        model.dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 || value.predictedEndTranslation.height > 120 {
                        MobileHaptics.trigger(.medium)
                        withAnimation(FluidTheme.fluidSpring) {
                            isPresented = false
                            model.dragOffset = 0
                        }
                    } else {
                        withAnimation(FluidTheme.fluidSpring) {
                            model.dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Auxiliary Control Pills (Romaji, Translate, Story & Sync)

    private func lyricsAuxiliaryBar(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Romaji / Transliteration Pill
            Button {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleRomanization()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "character.phonetic")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Romaji")
                        .font(.system(size: 11, weight: player.showRomanization ? .bold : .medium, design: .rounded))
                }
                .foregroundColor(player.showRomanization ? .white : (colorScheme == .light ? .primary : .white.opacity(0.8)))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(player.showRomanization ? FluidTheme.musicRed : (colorScheme == .light ? Color.primary.opacity(0.08) : Color.white.opacity(0.14)))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)

            // AI Translation Pill
            Button {
                MobileHaptics.trigger(.selection)
                player.toggleTranslation()
            } label: {
                HStack(spacing: 4) {
                    if player.isTranslatingLyrics {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .light ? FluidTheme.musicRed : .white))
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Translate")
                        .font(.system(size: 11, weight: player.showTranslation ? .bold : .medium, design: .rounded))
                }
                .foregroundColor(player.showTranslation ? .white : (colorScheme == .light ? .primary : .white.opacity(0.8)))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(player.showTranslation ? FluidTheme.musicRed : (colorScheme == .light ? Color.primary.opacity(0.08) : Color.white.opacity(0.14)))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .animation(nil, value: player.isTranslatingLyrics)

            // Music DNA Song Story Pill
            Button {
                withAnimation(FluidTheme.fluidSpring) {
                    player.toggleTrackStory()
                }
            } label: {
                HStack(spacing: 4) {
                    if player.isLoadingStory {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .light ? FluidTheme.musicRed : .white))
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Story")
                        .font(.system(size: 11, weight: player.showTrackStory ? .bold : .medium, design: .rounded))
                }
                .foregroundColor(player.showTrackStory ? .white : (colorScheme == .light ? .primary : .white.opacity(0.8)))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(player.showTrackStory ? FluidTheme.musicRed : (colorScheme == .light ? Color.primary.opacity(0.08) : Color.white.opacity(0.14)))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)

            // Sync Offset Adjuster Menu
            Menu {
                Button {
                    player.adjustLyricOffset(by: -0.5)
                } label: {
                    Label("Earlier (-0.5s)", systemImage: "minus.circle")
                }

                Button {
                    player.adjustLyricOffset(by: +0.5)
                } label: {
                    Label("Later (+0.5s)", systemImage: "plus.circle")
                }

                if player.userLyricOffset != 0 {
                    Button {
                        player.resetLyricOffset()
                    } label: {
                        Label("Reset Offset", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                    Text(player.userLyricOffset == 0 ? "Sync" : String(format: "%+.1fs", player.userLyricOffset))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(player.userLyricOffset != 0 ? .white : (colorScheme == .light ? Color.primary.opacity(0.8) : Color.white.opacity(0.8)))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(player.userLyricOffset != 0 ? FluidTheme.musicRed.opacity(0.9) : (colorScheme == .light ? Color.primary.opacity(0.08) : Color.white.opacity(0.14)))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)

            // Reload Lyrics Pill
            Button {
                MobileHaptics.trigger(.selection)
                if let track = player.currentTrack {
                    Task {
                        await player.loadLyrics(for: track)
                        MobileToastManager.shared.show(message: "Lyrics Refreshed", icon: "arrow.clockwise")
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .light ? Color.primary.opacity(0.8) : Color.white.opacity(0.8))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .light ? Color.primary.opacity(0.08) : Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Reload Lyrics")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Track Story Drawer Card

    private func trackStoryDrawer(width: CGFloat) -> some View {
        let story = player.trackStory
        let isLight = colorScheme == .light

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("Track Story & Meaning")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isLight ? .primary : .white)

                if let genre = story?.genre {
                    Text(genre)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                if let year = story?.releaseYear {
                    Text(year)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isLight ? Color.primary.opacity(0.08) : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button {
                    withAnimation(FluidTheme.fluidSpring) {
                        player.showTrackStory = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let story = story {
                Text(story.summary)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isLight ? .primary : .white.opacity(0.85))
                    .lineLimit(3)
            } else if player.isLoadingStory {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Fetching Wikipedia & Genius background...")
                        .font(.system(size: 11))
                        .foregroundColor(isLight ? .secondary : .white.opacity(0.7))
                }
                .padding(.vertical, 4)
            } else {
                Text("No story found for this track.")
                    .font(.system(size: 11))
                    .foregroundColor(isLight ? .secondary : .white.opacity(0.6))
            }
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isLight ? Color.platformSecondarySystemBackground : Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Large Artwork Stage (Horizontal Slide-and-Fade Transitions)

    @ViewBuilder
    private func singleArtworkCard(track: Track, size: CGFloat, isLight: Bool) -> some View {
        TrackArtworkView(
            url: track.artworkURL,
            contentMode: .fill,
            cornerRadius: 22,
            placeholderIconSize: 50
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(isLight ? 0.20 : 0.40), radius: 20, x: 0, y: 10)
        .scaleEffect(player.isPlaying ? 1.0 : 0.92)
        .animation(FluidTheme.fluidSpring, value: player.isPlaying)
    }

    private func largeArtworkView(size: CGFloat) -> some View {
        let isLight = colorScheme == .light
        let travel = size * 0.75
        let nextTrack = player.getNextTrackInQueue()
        let prevTrack = player.getPreviousTrackInQueue()

        return ZStack {
            if player.isCrossfading, let outgoing = player.outgoingTrack, let incoming = player.incomingTrack {
                // MARK: 1. Natural Track-End Audio Crossfade
                // Pure horizontal glide along X-axis: outgoing slides away and dissolves out, incoming enters and dissolves in
                let p = CGFloat(player.crossfadeProgress)
                let isFwd = player.slideDirection == .forward

                singleArtworkCard(track: outgoing, size: size, isLight: isLight)
                    .offset(x: isFwd ? -p * travel : p * travel)
                    .opacity(Double(max(0.0, 1.0 - p)))

                singleArtworkCard(track: incoming, size: size, isLight: isLight)
                    .offset(x: isFwd ? (1.0 - p) * travel : -(1.0 - p) * travel)
                    .opacity(Double(min(1.0, p)))

            } else if model.isTransitioningArtwork, let outgoing = model.transitionOutgoingTrack, let incoming = model.transitionIncomingTrack {
                // MARK: 2. Active Horizontal Slide-and-Fade Transition (Buttons or Released Flick)
                // Exactly what the user requested:
                // One album art goes to the left/right and fades out, and from the opposite side the new album comes in and fades in!
                let p = model.transitionProgress
                let isFwd = model.transitionDirection == .forward

                singleArtworkCard(track: outgoing, size: size, isLight: isLight)
                    .offset(x: isFwd ? -p * travel : p * travel)
                    .opacity(Double(max(0.0, 1.0 - p)))

                singleArtworkCard(track: incoming, size: size, isLight: isLight)
                    .offset(x: isFwd ? (1.0 - p) * travel : -(1.0 - p) * travel)
                    .opacity(Double(min(1.0, p)))

            } else if model.isDraggingArtwork && model.artworkDragOffset != 0 {
                // MARK: 3. Interactive Finger Dragging State (Tracks finger 1:1)
                let dx = model.artworkDragOffset
                let isFwd = dx < 0
                let p = min(1.0, max(0.0, abs(dx) / travel))
                let targetTrack = isFwd ? nextTrack : prevTrack

                if let current = player.currentTrack {
                    singleArtworkCard(track: current, size: size, isLight: isLight)
                        .offset(x: dx)
                        .opacity(targetTrack != nil ? Double(max(0.0, 1.0 - p)) : 1.0)
                }

                if let target = targetTrack {
                    singleArtworkCard(track: target, size: size, isLight: isLight)
                        .offset(x: isFwd ? travel + dx : -travel + dx)
                        .opacity(Double(p))
                }
            } else {
                // MARK: 4. Steady State (Only current track, centered, fully opaque)
                if let current = player.currentTrack {
                    singleArtworkCard(track: current, size: size, isLight: isLight)
                        .offset(x: 0)
                        .opacity(1.0)
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: size, height: size)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.showLyrics else { return }
            guard !model.isTransitioningArtwork, !model.isDraggingArtwork, abs(model.artworkDragOffset) < 4 else { return }
            MobileHaptics.trigger(.heavy)
            withAnimation(FluidTheme.fluidSpring) {
                player.togglePlayPause()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard !model.showLyrics else { return }
                    guard !model.isTransitioningArtwork else { return }

                    let dx = value.translation.width
                    let dy = value.translation.height

                    if !model.isDraggingArtwork {
                        if abs(dx) > abs(dy) * 1.1 && abs(dx) > 8 {
                            model.isDraggingArtwork = true
                        }
                    }

                    guard model.isDraggingArtwork else { return }

                    // Rubber-band resistance at boundaries if no track exists in that direction
                    if dx < 0 && nextTrack == nil {
                        model.artworkDragOffset = -min(20.0, pow(abs(dx), 0.6) * 1.1)
                    } else if dx > 0 && prevTrack == nil {
                        model.artworkDragOffset = min(20.0, pow(abs(dx), 0.6) * 1.1)
                    } else {
                        model.artworkDragOffset = dx
                    }
                }
                .onEnded { value in
                    guard model.isDraggingArtwork else { return }

                    let dx = model.artworkDragOffset
                    let predicted = value.predictedEndTranslation.width
                    let threshold: CGFloat = 55

                    // 1. Boundary on first track: pulling right when no previous track exists
                    if dx > 0 && prevTrack == nil {
                        MobileHaptics.trigger(.selection)
                        if player.currentTime > 0 { player.seek(to: 0) }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            model.artworkDragOffset = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            model.isDraggingArtwork = false
                        }
                        return
                    }

                    // 2. Boundary on last track: pulling left when no next track exists
                    if dx < 0 && nextTrack == nil {
                        MobileHaptics.trigger(.selection)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            model.artworkDragOffset = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            model.isDraggingArtwork = false
                        }
                        return
                    }

                    // 3. Flick / Swipe Left -> Next Track (Smooth slide out to left, slide in from right)
                    if (dx < -threshold || predicted < -100), let next = nextTrack {
                        MobileHaptics.trigger(.medium)
                        let startProgress = min(1.0, max(0.0, abs(dx) / travel))
                        model.isDraggingArtwork = false
                        model.artworkDragOffset = 0
                        model.transitionOutgoingTrack = player.currentTrack
                        model.transitionIncomingTrack = next
                        model.transitionDirection = .forward
                        model.transitionProgress = startProgress
                        model.isTransitioningArtwork = true

                        let remainingDuration = max(0.12, 0.24 * Double(1.0 - startProgress))
                        withAnimation(.easeOut(duration: remainingDuration)) {
                            model.transitionProgress = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDuration) {
                            player.slideDirection = .forward
                            player.forceNextTrack()
                            model.isTransitioningArtwork = false
                            model.transitionOutgoingTrack = nil
                            model.transitionIncomingTrack = nil
                            model.transitionProgress = 0.0
                        }
                    } else if (dx > threshold || predicted > 100), let prev = prevTrack {
                        // 4. Flick / Swipe Right -> Previous Track (Smooth slide out to right, slide in from left)
                        MobileHaptics.trigger(.medium)
                        let startProgress = min(1.0, max(0.0, dx / travel))
                        model.isDraggingArtwork = false
                        model.artworkDragOffset = 0
                        model.transitionOutgoingTrack = player.currentTrack
                        model.transitionIncomingTrack = prev
                        model.transitionDirection = .backward
                        model.transitionProgress = startProgress
                        model.isTransitioningArtwork = true

                        let remainingDuration = max(0.12, 0.24 * Double(1.0 - startProgress))
                        withAnimation(.easeOut(duration: remainingDuration)) {
                            model.transitionProgress = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDuration) {
                            player.slideDirection = .backward
                            player.forcePreviousTrack()
                            model.isTransitioningArtwork = false
                            model.transitionOutgoingTrack = nil
                            model.transitionIncomingTrack = nil
                            model.transitionProgress = 0.0
                        }
                    } else {
                        // 5. Incomplete gesture -> smoothly return current card to center
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            model.artworkDragOffset = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            model.isDraggingArtwork = false
                        }
                    }
                }
        )
    }

    // MARK: - Scrolling Karaoke Lyrics Stage

    private func scrollingLyricsView(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Sync Status Indicator Pill
                    if !player.lyricLines.isEmpty {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(player.isLyricsSynced ? FluidTheme.musicRed : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(player.isLyricsSynced ? "Synced Karaoke" : "Unsynced Full Text")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(colorScheme == .light ? Color.secondary : Color.white.opacity(0.65))

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                    }

                    if player.lyricLines.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.mic")
                                .font(.system(size: 36))
                                .foregroundColor(colorScheme == .light ? Color.secondary.opacity(0.5) : Color.white.opacity(0.5))

                            Text(player.isLoadingLyrics ? "Loading synchronized lyrics..." : "No synchronized lyrics available.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .light ? Color.secondary : Color.white.opacity(0.65))
                                .multilineTextAlignment(.center)

                            if !player.isLoadingLyrics {
                                Button {
                                    MobileHaptics.trigger(.medium)
                                    if let track = player.currentTrack {
                                        Task {
                                            await player.loadLyrics(for: track)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry Lyrics")
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(FluidTheme.musicRed)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(width: width)
                        .frame(minHeight: 180)
                    } else {
                        ForEach(player.lyricLines) { line in
                            let isActive = player.isLyricsSynced && (player.activeLyricIndex >= 0 && player.activeLyricIndex < player.lyricLines.count && player.lyricLines[player.activeLyricIndex].id == line.id)

                            VStack(alignment: .leading, spacing: 3) {
                                // 1. Phonetic Romanization (Romaji / Pinyin)
                                if player.showRomanization, let romaji = line.romanization, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: isActive ? 13 : 11, weight: .medium, design: .rounded))
                                        .foregroundColor(isActive ? FluidTheme.musicRed.opacity(0.9) : (colorScheme == .light ? Color.secondary : Color.white.opacity(0.40)))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(width: width, alignment: .leading)
                                }

                                // 2. Main Synchronized Lyric Line
                                Text(line.text)
                                    .font(.system(size: isActive ? 26 : 18, weight: isActive ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isActive ? (colorScheme == .light ? Color.primary : Color.white) : (colorScheme == .light ? Color.primary.opacity(0.38) : Color.white.opacity(player.isLyricsSynced ? 0.42 : 0.75)))
                                    .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: width, alignment: .leading)

                                // 3. AI Translation Subtitle
                                if player.showTranslation, let translation = line.translation, !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: isActive ? 14 : 13, weight: isActive ? .medium : .regular, design: .rounded))
                                        .foregroundColor(isActive ? (colorScheme == .light ? Color.primary.opacity(0.9) : Color.white.opacity(0.9)) : (colorScheme == .light ? Color.secondary : Color.white.opacity(0.40)))
                                        .italic()
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(width: width, alignment: .leading)
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if player.isLyricsSynced && line.time > 0 {
                                    MobileHaptics.trigger(.selection)
                                    player.seek(to: line.time)
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: player.showTranslation)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(width: width + 48, alignment: .leading)
            }
            .frame(width: width + 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: player.activeLyricIndex) { _, newIndex in
                guard player.isLyricsSynced,
                      newIndex >= 0,
                      newIndex < player.lyricLines.count else { return }
                let targetId = player.lyricLines[newIndex].id
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Track Metadata Row

    private func metadataRow(width: CGFloat) -> some View {
        let activeTrack: Track? = {
            if player.isCrossfading {
                return (player.crossfadeProgress < 0.5) ? (player.outgoingTrack ?? player.currentTrack) : (player.incomingTrack ?? player.currentTrack)
            }
            return player.currentTrack
        }()

        let metadataOpacity: Double = {
            if player.isCrossfading {
                let p = player.crossfadeProgress
                return p < 0.5 ? max(0.2, 1.0 - (p * 2.0)) : min(1.0, 0.2 + (p - 0.5) * 2.0 * 0.8)
            }
            return 1.0
        }()

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activeTrack?.title ?? "Sonorist")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .light ? .primary : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(metadataOpacity)

                HStack(spacing: 6) {
                    if activeTrack?.isCached == true {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(FluidTheme.downloadGreen)
                    }

                    Text(activeTrack?.artist ?? "Select a track to play")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .opacity(metadataOpacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if let track = activeTrack {
                Button {
                    MobileHaptics.trigger(.heavy)
                    player.toggleLike(track: track)
                } label: {
                    Image(systemName: player.isLiked(track: track) ? "heart.fill" : "heart")
                        .font(.system(size: 24))
                        .foregroundColor(player.isLiked(track: track) ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.7)))
                        .frame(width: 44, height: 44)
                        .scaleEffect(player.isLiked(track: track) ? 1.15 : 1.0)
                        .animation(FluidTheme.tapSpring, value: player.isLiked(track: track))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(width: width)
    }

    // MARK: - Animated Track Navigations (Synchronized Horizontal Slide-and-Fade)

    private func animateToNextTrack(size: CGFloat) {
        guard !model.isTransitioningArtwork, !model.isDraggingArtwork else { return }
        guard let next = player.getNextTrackInQueue() else {
            // Subtle edge rubber-band bounce when no next track exists
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                model.artworkDragOffset = -18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    model.artworkDragOffset = 0
                }
            }
            return
        }

        MobileHaptics.trigger(.medium)
        model.transitionOutgoingTrack = player.currentTrack
        model.transitionIncomingTrack = next
        model.transitionDirection = .forward
        model.transitionProgress = 0.0
        model.isTransitioningArtwork = true

        withAnimation(.easeInOut(duration: 0.26)) {
            model.transitionProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            player.slideDirection = .forward
            player.forceNextTrack()
            model.isTransitioningArtwork = false
            model.transitionOutgoingTrack = nil
            model.transitionIncomingTrack = nil
            model.transitionProgress = 0.0
        }
    }

    private func animateToPreviousTrack(size: CGFloat) {
        guard !model.isTransitioningArtwork, !model.isDraggingArtwork else { return }

        // Apple Music HIG: If more than 3 seconds into track, rewind to start
        if player.currentTime > 3.0 {
            MobileHaptics.trigger(.medium)
            player.seek(to: 0)
            return
        }

        guard let prev = player.getPreviousTrackInQueue() else {
            MobileHaptics.trigger(.selection)
            if player.currentTime > 0 { player.seek(to: 0) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                model.artworkDragOffset = 18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    model.artworkDragOffset = 0
                }
            }
            return
        }

        MobileHaptics.trigger(.medium)
        model.transitionOutgoingTrack = player.currentTrack
        model.transitionIncomingTrack = prev
        model.transitionDirection = .backward
        model.transitionProgress = 0.0
        model.isTransitioningArtwork = true

        withAnimation(.easeInOut(duration: 0.26)) {
            model.transitionProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            player.slideDirection = .backward
            player.forcePreviousTrack()
            model.isTransitioningArtwork = false
            model.transitionOutgoingTrack = nil
            model.transitionIncomingTrack = nil
            model.transitionProgress = 0.0
        }
    }

    // MARK: - Transport Controls

    private func transportControls(width: CGFloat, artworkSize: CGFloat) -> some View {
        HStack(spacing: 34) {
            Button {
                MobileHaptics.trigger(.light)
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19))
                    .foregroundColor(player.isShuffle ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.65)))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                animateToPreviousTrack(size: artworkSize)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(colorScheme == .light ? .primary : .white)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                MobileHaptics.trigger(.heavy)
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(FluidTheme.musicRed)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                animateToNextTrack(size: artworkSize)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(colorScheme == .light ? .primary : .white)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                MobileHaptics.trigger(.light)
                player.toggleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19))
                    .foregroundColor(player.repeatMode != .off ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.65)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: width)
    }

    // MARK: - Bottom Accessories (Apple Music 3-Control Standard)

    private func bottomAccessoryBar(width: CGFloat) -> some View {
        HStack {
            // 1. Lyrics Toggle (Left)
            Button {
                MobileHaptics.trigger(.selection)
                withAnimation(.easeInOut(duration: 0.3)) {
                    model.showLyrics.toggle()
                }
                ensureLyricsLoaded()
            } label: {
                Image(systemName: model.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(model.showLyrics ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.65)))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Lyrics")

            Spacer()

            // 2. AirPlay Destination Picker (Center - Iconic Apple AirPlay symbol)
            ZStack {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.65))
                    .frame(width: 44, height: 44)

                #if os(iOS)
                AirPlayRoutePickerOverlay()
                    .frame(width: 44, height: 44)
                #endif
            }
            .accessibilityLabel("AirPlay Audio Destination")

            Spacer()

            // 3. Up Next Queue Button (Right)
            Button {
                MobileHaptics.trigger(.selection)
                model.showQueueSheet = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(model.showQueueSheet ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.65)))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Playing Next Queue")
        }
        .frame(width: width)
    }

    // MARK: - Helper Methods

    private func ensureLyricsLoaded() {
        if player.lyricLines.isEmpty, let track = player.currentTrack {
            Task {
                await player.loadLyrics(for: track)
            }
        }
    }

    private func loadDemoLyrics() {
        let cur = player.currentTime
        player.lyricLines = [
            LyricLine(id: "1", time: max(0, cur - 6), text: "I can hear the music in the air"),
            LyricLine(id: "2", time: max(0, cur - 3), text: "Drifting through the quiet of the night"),
            LyricLine(id: "3", time: cur, text: "Every beat is taking me higher"),
            LyricLine(id: "4", time: cur + 4, text: "Feel the rhythm moving through your soul"),
            LyricLine(id: "5", time: cur + 8, text: "Lost in the melody, letting it go"),
            LyricLine(id: "6", time: cur + 12, text: "Pure sound, nothing else matters now"),
            LyricLine(id: "7", time: cur + 16, text: "Let the harmony carry us away")
        ]
        player.isLyricsSynced = true
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Isolated Scrubber Section
// Observes PlaybackProgressTracker independently so that high-frequency audio clock ticks (4Hz)
// update ONLY this scrubber view and do not cause the entire modal sheet or menus to re-render.

private struct NowPlayingScrubberSection: View {
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    @ObservedObject private var model = MobileNowPlayingSheetModel.shared

    var body: some View {
        VStack(spacing: 8) {
            let current: Double = {
                let val = model.isSeeking ? model.seekPosition : progressTracker.currentTime
                guard val.isFinite && !val.isNaN && val >= 0 else { return 0 }
                return val
            }()
            let ratio: Double = {
                guard player.duration > 0 && player.duration.isFinite && !player.duration.isNaN else { return 0 }
                return max(0, min(current / player.duration, 1.0))
            }()

            // Interactive Scrubber Bar
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(colorScheme == .light ? Color.primary.opacity(0.12) : Color.white.opacity(0.24))
                    .frame(width: width, height: 5)

                // Active Progress Track
                Capsule()
                    .fill(FluidTheme.musicRed)
                    .frame(width: max(0, min(width * CGFloat(ratio), width)), height: 5)

                // Scrubber Thumb Handle
                Circle()
                    .fill(colorScheme == .light ? Color.primary : Color.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(width * CGFloat(ratio) - 7, width - 15)))
            }
            .frame(width: width, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.isSeeking = true
                        let progress = max(0, min(value.location.x / width, 1.0))
                        model.seekPosition = progress * max(1, player.duration)
                    }
                    .onEnded { value in
                        let progress = max(0, min(value.location.x / width, 1.0))
                        player.seek(to: progress * max(1, player.duration))
                        model.isSeeking = false
                    }
            )

            // Timestamps: Elapsed (left) & Remaining (right)
            HStack {
                Text(formatDuration(current))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.75))

                Spacer()

                let remaining = max(0, player.duration - current)
                Text("-" + formatDuration(remaining))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.75))
            }
            .frame(width: width)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Isolated Header & Ellipsis Menu
// Completely isolated and Equatable so playback progress ticks and lyric line updates
// do NOT trigger re-renders, preventing the open UIMenu from flickering or closing.

private struct NowPlayingHeaderRow: View, Equatable {
    let width: CGFloat
    let isOffline: Bool
    let albumTitle: String
    let currentTrack: Track?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var player = AudioPlayerEngine.shared

    static func == (lhs: NowPlayingHeaderRow, rhs: NowPlayingHeaderRow) -> Bool {
        lhs.width == rhs.width &&
        lhs.isOffline == rhs.isOffline &&
        lhs.albumTitle == rhs.albumTitle &&
        lhs.currentTrack?.id == rhs.currentTrack?.id &&
        lhs.player.sleepTimerRemainingSeconds == rhs.player.sleepTimerRemainingSeconds
    }

    var body: some View {
        HStack {
            // Bedtime Sleep Timer Button (Top-Left Quick Access)
            Button {
                MobileHaptics.trigger(.selection)
                MobileNowPlayingSheetModel.shared.showSleepTimerSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: player.sleepTimerRemainingSeconds > 0 ? "moon.stars.fill" : "moon.fill")
                        .font(.system(size: 20))
                        .foregroundColor(player.sleepTimerRemainingSeconds > 0 ? FluidTheme.musicRed : (colorScheme == .light ? .secondary : .white.opacity(0.8)))
                        .frame(width: 44, height: 44)

                    if player.sleepTimerRemainingSeconds > 0 {
                        Circle()
                            .fill(FluidTheme.musicRed)
                            .frame(width: 7, height: 7)
                            .padding(.top, 9)
                            .padding(.trailing, 9)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(player.sleepTimerRemainingSeconds > 0 ? "Sleep Timer: \(player.formattedSleepTimerRemaining)" : "Sleep Timer")

            Spacer()

            VStack(spacing: 2) {
                Text(isOffline ? "PLAYING OFFLINE" : "PLAYING FROM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.55))
                    .tracking(1.0)

                Text(albumTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .light ? .primary : .white)
                    .lineLimit(1)
            }

            Spacer()

            NowPlayingEllipsisMenu(track: currentTrack)
                .equatable()
        }
        .frame(width: width)
    }
}

private struct NowPlayingEllipsisMenu: View, Equatable {
    let track: Track?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var player = AudioPlayerEngine.shared

    static func == (lhs: NowPlayingEllipsisMenu, rhs: NowPlayingEllipsisMenu) -> Bool {
        lhs.track?.id == rhs.track?.id &&
        lhs.player.equalizerPreset == rhs.player.equalizerPreset
    }

    var body: some View {
        Menu {
            Button {
                MobileHaptics.trigger(.selection)
                MobileNowPlayingSheetModel.shared.showEqualizerSheet = true
            } label: {
                Label("Equalizer (\(player.equalizerPreset))", systemImage: "slider.vertical.3")
            }

            if let track = track, let shareURL = URL(string: "https://music.youtube.com/watch?v=\(track.id)") {
                Divider()

                ShareLink(item: shareURL, subject: Text(track.title), message: Text("Listen to \(track.title) by \(track.artist) on Sonorist")) {
                    Label("Share Song", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(colorScheme == .light ? .secondary : .white.opacity(0.8))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Mobile Queue Sheet (Up Next)

public struct MobileQueueSheet: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var effectiveColorScheme: ColorScheme {
        themeManager.currentTheme.colorScheme ?? colorScheme
    }

    private var isLight: Bool {
        effectiveColorScheme == .light
    }

    private var currentTrackIndex: Int? {
        guard let current = player.currentTrack else { return nil }
        return player.queue.firstIndex(where: { $0.id == current.id })
    }

    private struct QueueRowEntry: Identifiable {
        let id: String
        let queueIndex: Int
        let track: Track
    }

    private var upNextEntries: [QueueRowEntry] {
        guard !player.queue.isEmpty else { return [] }
        let startIndex = (currentTrackIndex.map { $0 + 1 }) ?? 0
        guard startIndex < player.queue.count else { return [] }
        return (startIndex..<player.queue.count).map { idx in
            QueueRowEntry(id: "\(player.queue[idx].id)_\(idx)", queueIndex: idx, track: player.queue[idx])
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // 1. Currently Playing Section
                if let current = player.currentTrack {
                    Section {
                        HStack(spacing: 12) {
                            TrackArtworkView(
                                url: current.artworkURL,
                                contentMode: .fill,
                                cornerRadius: 8,
                                placeholderIconSize: 20
                            )
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(current.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(FluidTheme.musicRed)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    if current.isCached {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(FluidTheme.downloadGreen)
                                    }
                                    Text(current.artist)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(isLight ? Color.secondary : Color.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(FluidTheme.musicRed)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                        )
                    } header: {
                        Text("NOW PLAYING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }

                // 2. Up Next Section
                Section {
                    if upNextEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("No Upcoming Songs")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("Add songs from Search or Library to keep music playing.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                        )
                    } else {
                        ForEach(upNextEntries) { entry in
                            Button {
                                MobileHaptics.trigger(.medium)
                                player.play(track: entry.track)
                            } label: {
                                HStack(spacing: 12) {
                                    TrackArtworkView(
                                        url: entry.track.artworkURL,
                                        contentMode: .fill,
                                        cornerRadius: 6,
                                        placeholderIconSize: 16
                                    )
                                    .frame(width: 42, height: 42)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.track.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(isLight ? .primary : .white)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            if entry.track.isCached {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(FluidTheme.downloadGreen)
                                            }
                                            Text(entry.track.artist)
                                                .font(.system(size: 12))
                                                .foregroundColor(isLight ? .secondary : .white.opacity(0.65))
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "play.circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(isLight ? .secondary : .white.opacity(0.5))
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                            )
                        }
                        .onDelete { indexSet in
                            for offset in indexSet {
                                if offset < upNextEntries.count {
                                    let targetIndex = upNextEntries[offset].queueIndex
                                    player.removeFromQueue(at: targetIndex)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(player.isPlayingFromOfflineLibrary ? "UP NEXT • OFFLINE LIBRARY (\(upNextEntries.count))" : "UP NEXT • YOUTUBE MUSIC RADIO (\(upNextEntries.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !upNextEntries.isEmpty {
                            Button("Clear") {
                                MobileHaptics.trigger(.medium)
                                if let start = currentTrackIndex.map({ $0 + 1 }) {
                                    if start < player.queue.count {
                                        player.queue.removeSubrange(start..<player.queue.count)
                                        player.saveCurrentPlaybackState()
                                    }
                                } else {
                                    player.clearQueue()
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FluidTheme.musicRed)
                        }
                    }
                }

                // 3. Autoplay Radio Toggle
                Section {
                    Toggle(isOn: $player.isAutoplayEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Infinite Autoplay")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(isLight ? .primary : .white)
                            Text("Similar songs keep playing when queue ends")
                                .font(.system(size: 12))
                                .foregroundColor(isLight ? .secondary : .white.opacity(0.65))
                        }
                    }
                    .tint(FluidTheme.musicRed)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                    )
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .background(
                Color.platformSystemBackground
                    .ignoresSafeArea()
            )
            .navigationTitle("Playing Next")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
                }
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        #if os(iOS)
        .presentationBackground(Color.platformSystemBackground)
        #endif
    }
}

// MARK: - Equatable Ambient Artwork Backdrop (Prevents Re-Rendering Heavy 60px Blur)

public struct AmbientArtworkBackdrop: View, Equatable {
    let artworkURL: URL?
    let colorScheme: ColorScheme

    public static func == (lhs: AmbientArtworkBackdrop, rhs: AmbientArtworkBackdrop) -> Bool {
        lhs.artworkURL == rhs.artworkURL && lhs.colorScheme == rhs.colorScheme
    }

    public var body: some View {
        ZStack {
            Color.platformSystemBackground

            if let url = artworkURL {
                #if os(iOS)
                if url.isFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(colorScheme == .light ? 1.35 : 1.0)
                        .blur(radius: colorScheme == .light ? 50 : 60)
                        .opacity(colorScheme == .light ? 0.55 : 0.48)
                } else {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .saturation(colorScheme == .light ? 1.35 : 1.0)
                                .blur(radius: colorScheme == .light ? 50 : 60)
                                .opacity(colorScheme == .light ? 0.55 : 0.48)
                        }
                    }
                }
                #else
                if url.isFileURL, let nsImage = NSImage(contentsOfFile: url.path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(colorScheme == .light ? 1.35 : 1.0)
                        .blur(radius: colorScheme == .light ? 50 : 60)
                        .opacity(colorScheme == .light ? 0.55 : 0.48)
                } else {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .saturation(colorScheme == .light ? 1.35 : 1.0)
                                .blur(radius: colorScheme == .light ? 50 : 60)
                                .opacity(colorScheme == .light ? 0.55 : 0.48)
                        }
                    }
                }
                #endif
            }

            if colorScheme == .light {
                Color.platformSystemBackground
                    .opacity(0.68)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.85)
            }
        }
    }
}
