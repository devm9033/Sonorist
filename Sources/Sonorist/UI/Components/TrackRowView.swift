import SwiftUI
import Combine

public final class RowHoverState: ObservableObject {
    @Published public var isHovered: Bool = false
    public init() {}
}

public struct TrackRowView: View {
    public let track: Track
    public let isCurrent: Bool
    public let isPlaying: Bool
    public let onPlay: () -> Void
    public let onRemoveDownload: (() -> Void)?
    
    @ObservedObject private var hoverState: RowHoverState
    @ObservedObject private var player = AudioPlayerEngine.shared
    
    public init(
        track: Track,
        isCurrent: Bool = false,
        isPlaying: Bool = false,
        hoverState: RowHoverState = RowHoverState(),
        onRemoveDownload: (() -> Void)? = nil,
        onPlay: @escaping () -> Void
    ) {
        self.track = track
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.hoverState = hoverState
        self.onRemoveDownload = onRemoveDownload
        self.onPlay = onPlay
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Clickable Artwork & Metadata Left Area
            HStack(spacing: 14) {
                // Artwork with play/pause overlay
                ZStack {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            Color.gray.opacity(0.3)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.secondary)
                                )
                        @unknown default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                    
                    if hoverState.isHovered || isCurrent {
                        Color.black.opacity(0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Image(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 48, height: 48)
                
                // Track metadata
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isCurrent && isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FluidTheme.musicRed)
                        }
                        Text(track.title)
                            .font(FluidTheme.headlineFont)
                            .lineLimit(1)
                            .foregroundColor(isCurrent ? FluidTheme.musicRed : .primary)
                    }
                    
                    HStack(spacing: 6) {
                        Text(track.artist)
                            .font(FluidTheme.captionFont)
                            .foregroundColor(FluidTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Like Button (Expanded 28×28 Apple tactile hit target)
            Button(action: {
                withAnimation(FluidTheme.tapSpring) {
                    player.toggleLike(track: track)
                }
            }) {
                Image(systemName: player.isLiked(track: track) ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundColor(player.isLiked(track: track) ? FluidTheme.musicRed : .secondary.opacity(0.6))
            }
            .buttonStyle(ApplePlayerButtonStyle(width: 28, height: 28, cornerRadius: 6))
            .help(player.isLiked(track: track) ? "Remove from Favorites" : "Add to Favorites")
            
            // Auto-saved offline status indicator (No manual download button needed)
            let isDownloaded = track.isCached || MediaCacheManager.shared.isCached(videoId: track.id)
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.green.opacity(0.9))
                    .help("Automatically saved offline in compressed .sonorist library")
            }
            
            // Formatted duration
            Text(track.formattedDuration)
                .font(FluidTheme.captionFont)
                .monospacedDigit()
                .foregroundColor(FluidTheme.secondaryText)
                .frame(width: 45, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? FluidTheme.musicRed.opacity(0.08) : (hoverState.isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("Play Now", systemImage: "play.fill")
            }
            
            Button {
                player.playNext(track: track)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button {
                player.addToQueue(track: track)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            
            Divider()
            
            Button {
                player.toggleLike(track: track)
            } label: {
                Label(player.isLiked(track: track) ? "Remove from Favorites" : "Add to Favorites", systemImage: player.isLiked(track: track) ? "heart.slash" : "heart")
            }
            
            let isCachedTrack = track.isCached || MediaCacheManager.shared.isCached(videoId: track.id)
            if isCachedTrack {
                Divider()
                
                Button {
                    exportTrackToFinder(track: track)
                } label: {
                    Label("Export to Finder (.m4a)...", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    onRemoveDownload?()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
        .onHover { hovering in
            withAnimation(FluidTheme.fluidSpring) {
                hoverState.isHovered = hovering
            }
        }
    }
    
    private func exportTrackToFinder(track: Track) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export \"\(track.title)\""
        savePanel.prompt = "Export"
        let safeName = "\(track.artist) - \(track.title)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
        savePanel.nameFieldStringValue = "\(safeName).m4a"
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            do {
                try MediaCacheManager.shared.exportTrack(videoId: track.id, destinationURL: destinationURL)
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            } catch {
                #if DEBUG
                print("[Export failed]: \(error)")
                #endif
            }
        }
    }
}
