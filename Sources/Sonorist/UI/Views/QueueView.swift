import SwiftUI

@MainActor
public final class QueueViewModel: ObservableObject {
    public static let shared = QueueViewModel()
    @Published public var showClearQueueAlert: Bool = false
    public init() {}
}

public struct QueueView: View {
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var queueModel = QueueViewModel.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 22, height: 22)
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Up Next Queue")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("\(player.queue.count) tracks in queue")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Autoplay Radio Toggle Pill
                Button(action: {
                    FluidHaptics.tap()
                    withAnimation(FluidTheme.tapSpring) {
                        player.isAutoplayEnabled.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "infinity")
                            .font(.system(size: 10, weight: .bold))
                        Text(player.isAutoplayEnabled ? "Autoplay On" : "Autoplay Off")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(player.isAutoplayEnabled ? FluidTheme.musicRed.opacity(0.18) : Color.primary.opacity(0.08))
                    .foregroundColor(player.isAutoplayEnabled ? FluidTheme.musicRed : .secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help("When queue finishes, automatically play similar radio songs")
                
                if !player.queue.isEmpty {
                    Button("Clear All") {
                        FluidHaptics.tap()
                        queueModel.showClearQueueAlert = true
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(FluidTheme.musicRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FluidTheme.musicRed.opacity(0.10))
                    .clipShape(Capsule())
                    .help("Remove all upcoming tracks from queue")
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
                .help("Close Queue (Esc)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            
            Divider()
            
            if player.queue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Queue is Empty")
                        .font(FluidTheme.headlineFont)
                        .foregroundColor(.secondary)
                    Text("Play any song or search results to automatically populate the queue.")
                        .font(FluidTheme.captionFont)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 20, alignment: .leading)
                            
                            AsyncImage(url: track.artworkURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(FluidTheme.headlineFont)
                                    .lineLimit(1)
                                    .foregroundColor(player.currentTrack?.id == track.id ? FluidTheme.musicRed : .primary)
                                Text(track.artist)
                                    .font(FluidTheme.captionFont)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                FluidHaptics.tap()
                                withAnimation(FluidTheme.tapSpring) {
                                    player.removeFromQueue(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(ApplePlayerButtonStyle(width: 26, height: 26, cornerRadius: 5))
                            .help("Remove track from queue")
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(track: track)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(width: 420, height: 500)
        .background(FluidTheme.barMaterial)
        .alert("Clear Playing Queue?", isPresented: $queueModel.showClearQueueAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Queue", role: .destructive) {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.tapSpring) {
                    player.clearQueue()
                }
            }
        } message: {
            Text("This will remove all \(player.queue.count) upcoming songs from your queue. The currently playing track will continue.")
        }
    }
}
