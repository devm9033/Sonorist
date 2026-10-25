import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            if let track = player.currentTrack {
                HStack(spacing: 10) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text(track.audioFormat)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Progress Bar in Menu Bar (Isolated subview)
                MenuBarProgressBar()
                
                HStack(spacing: 20) {
                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if player.sleepTimerRemainingSeconds > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 10))
                        Text("Sleep timer: \(player.formattedSleepTimerRemaining)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                Text("No Track Playing")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            HStack {
                Button("Immersive View") {
                    withAnimation { player.isImmersiveViewActive = true }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 11, weight: .medium))
                
                Spacer()
                
                Button("Quit Sonorist") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

public struct MenuBarProgressBar: View {
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
