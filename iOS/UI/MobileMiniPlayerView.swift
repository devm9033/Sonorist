import SwiftUI

/// Floating MiniPlayer docked directly above the iOS Tab Bar.
/// Conforms to Apple Music iOS 18+ floating capsule design with interactive scrubbing progress.
/// Supports both tap-to-expand and 1:1 direct manipulation upward slide-to-expand gestures.
public struct MobileMiniPlayerView: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    public let screenHeight: CGFloat
    public let onTap: () -> Void
    
    public init(screenHeight: CGFloat = 852, onTap: @escaping () -> Void) {
        self.screenHeight = screenHeight
        self.onTap = onTap
    }
    
    public var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                // Top Micro-Progress Bar
                GeometryReader { geo in
                    let progress: Double = {
                        guard player.duration > 0 && player.duration.isFinite && !player.duration.isNaN else { return 0 }
                        let cur = progressTracker.currentTime
                        guard cur.isFinite && !cur.isNaN && cur >= 0 else { return 0 }
                        return max(0, min(cur / player.duration, 1.0))
                    }()
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(FluidTheme.musicRed)
                            .frame(width: max(0, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 2)
                    }
                }
                .frame(height: 2)
                
                // Main Content Row
                HStack(spacing: 12) {
                    // Artwork Thumbnail (Offline-first)
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 8,
                        placeholderIconSize: 14
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    
                    // Title & Artist (Tapping this expands Now Playing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Play/Pause Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Next Button
                    Button {
                        MobileHaptics.trigger(.light)
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(FluidTheme.glassMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            // 1:1 Interactive Slide-Up Drag Gesture — Glues the full Now Playing sheet to the finger
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height < 0 {
                            let coordinator = MobileNavigationCoordinator.shared
                            if !coordinator.isDraggingUpFromMiniPlayer {
                                coordinator.isDraggingUpFromMiniPlayer = true
                                MobileHaptics.trigger(.light)
                            }
                            // The full Now Playing sheet slides smoothly upward from screen bottom
                            let offset = max(0, screenHeight + value.translation.height)
                            coordinator.sheetDragOffset = offset
                        }
                    }
                    .onEnded { value in
                        let coordinator = MobileNavigationCoordinator.shared
                        if coordinator.isDraggingUpFromMiniPlayer {
                            // Fling upward or dragged past threshold
                            if value.translation.height < -65 || value.predictedEndTranslation.height < -140 {
                                MobileHaptics.trigger(.medium)
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.sheetDragOffset = 0
                                    coordinator.isNowPlayingExpanded = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    coordinator.isDraggingUpFromMiniPlayer = false
                                }
                            } else {
                                // Cancel and spring smoothly back off-screen
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.sheetDragOffset = screenHeight
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    coordinator.isDraggingUpFromMiniPlayer = false
                                    coordinator.isNowPlayingExpanded = false
                                }
                            }
                        }
                    }
            )
            // Tap gesture as instant fallback
            .onTapGesture {
                MobileHaptics.trigger(.medium)
                onTap()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
