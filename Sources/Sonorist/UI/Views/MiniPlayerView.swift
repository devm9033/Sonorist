import SwiftUI

/// Compact Apple Music-inspired floating MiniPlayer
/// Can be toggled with ⌘M or via toolbar button for unobtrusive desktop listening.
public struct MiniPlayerView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 8) {
            // Main Track & Controls Row
            HStack(spacing: 12) {
                // Artwork
                if let track = player.currentTrack {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.secondary.opacity(0.2)
                                .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(.secondary))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(radius: 4)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "music.quarternote.3").foregroundColor(.secondary))
                    
                    Text("No track playing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 12) {
                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        withAnimation(FluidTheme.fluidSpring) {
                            player.isMiniPlayerActive = false
                        }
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Return to Main Window")
                }
            }
            
            // Progress Bar (Isolated subview to avoid re-rendering entire miniplayer)
            MiniPlayerProgressBar()
        }
        .padding(12)
        .frame(width: 320, height: 76)
        .background(FluidTheme.glassMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

public struct MiniPlayerProgressBar: View {
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 3)
                
                let progress = player.duration > 0 ? progressTracker.currentTime / player.duration : 0
                Capsule()
                    .fill(FluidTheme.musicRed)
                    .frame(width: max(0, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 3)
            }
        }
        .frame(height: 3)
    }
}
