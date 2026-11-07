import SwiftUI

/// Floating MiniPlayer docked directly above the iOS Tab Bar.
/// Conforms to Apple Music iOS 18+ floating capsule design with interactive scrubbing progress.
/// Supports both tap-to-expand and 1:1 direct manipulation upward slide-to-expand gestures.
public struct MobileMiniPlayerView: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    @ObservedObject private var coordinator = MobileNavigationCoordinator.shared
    public let screenHeight: CGFloat
    public let onTap: () -> Void
    
    public init(screenHeight: CGFloat = 852, onTap: @escaping () -> Void) {
        self.screenHeight = screenHeight
        self.onTap = onTap
    }
    
    public var body: some View {
        if let track = player.currentTrack {
            let offset = coordinator.miniPlayerDownwardOffset
            let dismissProgress = min(1.0, max(0.0, offset / 60.0))
            
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
            .shadow(color: .black.opacity(0.18 * Double(1.0 - dismissProgress)), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .offset(y: offset)
            .opacity(1.0 - Double(dismissProgress * 0.95))
            .scaleEffect(1.0 - (dismissProgress * 0.05))
            .contentShape(Rectangle())
            // 1:1 Interactive Slide-Up Drag Gesture & Downward Flick Dismissal
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height < 0 {
                            // Upward gesture: direct manipulation expanding full sheet
                            coordinator.miniPlayerDownwardOffset = 0
                            if !coordinator.isDraggingUpFromMiniPlayer {
                                coordinator.isDraggingUpFromMiniPlayer = true
                                MobileHaptics.trigger(.light)
                            }
                            let sheetOffset = max(0, screenHeight + value.translation.height)
                            coordinator.sheetDragOffset = sheetOffset
                        } else if value.translation.height > 0 {
                            // Downward gesture
                            if coordinator.isDraggingUpFromMiniPlayer {
                                coordinator.isDraggingUpFromMiniPlayer = false
                            }
                            if !player.isPlaying {
                                // 1:1 Direct Manipulation tracking downward when idle/paused
                                coordinator.miniPlayerDownwardOffset = value.translation.height
                            } else {
                                // Rubber-band boundary cushioning when music is playing
                                coordinator.miniPlayerDownwardOffset = sqrt(value.translation.height) * 2.8
                            }
                        }
                    }
                    .onEnded { value in
                        if coordinator.isDraggingUpFromMiniPlayer {
                            // Upward sheet expansion
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
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.sheetDragOffset = screenHeight
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    coordinator.isDraggingUpFromMiniPlayer = false
                                    coordinator.isNowPlayingExpanded = false
                                }
                            }
                        } else if coordinator.miniPlayerDownwardOffset > 0 {
                            let curOffset = coordinator.miniPlayerDownwardOffset
                            // Downward flick handling
                            if !player.isPlaying && (curOffset > 30 || value.predictedEndTranslation.height > 60) {
                                // User flicked down to dismiss while paused
                                MobileHaptics.trigger(.light)
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.miniPlayerDownwardOffset = 80
                                    coordinator.isMiniPlayerDismissed = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    coordinator.miniPlayerDownwardOffset = 0
                                }
                            } else if player.isPlaying && (curOffset > 50 || value.predictedEndTranslation.height > 200) {
                                // Forceful downward flick while playing -> pause and dismiss
                                MobileHaptics.trigger(.medium)
                                player.pause()
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.miniPlayerDownwardOffset = 80
                                    coordinator.isMiniPlayerDismissed = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    coordinator.miniPlayerDownwardOffset = 0
                                }
                            } else {
                                // Spring back to rest position
                                withAnimation(FluidTheme.fluidSpring) {
                                    coordinator.miniPlayerDownwardOffset = 0
                                }
                            }
                        }
                    }
            )
            // Tap gesture as instant fallback (ignored during active drag)
            .onTapGesture {
                guard coordinator.miniPlayerDownwardOffset == 0 else { return }
                guard !coordinator.isDraggingUpFromMiniPlayer else { return }
                MobileHaptics.trigger(.medium)
                onTap()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
