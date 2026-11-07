import SwiftUI

public final class MobileLibraryModel: ObservableObject {
    public static let shared = MobileLibraryModel()
    @Published public var selectedSegment: MobileLibrarySegment = .downloaded
    @Published public var showSettings: Bool = false
    @Published public var showClearAllConfirmation: Bool = false
    @Published public var refreshID: UUID = UUID()
    @Published public var offlineTracks: [Track] = []
    
    public init() {
        self.offlineTracks = MediaCacheManager.shared.getAllCachedTracks()
        loadOfflineTracks()
    }
    
    public func loadOfflineTracks() {
        DispatchQueue.global(qos: .userInitiated).async {
            let tracks = MediaCacheManager.shared.getAllCachedTracks()
            DispatchQueue.main.async {
                self.offlineTracks = tracks
            }
        }
    }
}

public enum MobileLibrarySegment: String, CaseIterable, Identifiable {
    case downloaded = "Downloaded"
    case favorites = "Favorites"
    
    public var id: String { rawValue }
}

/// iOS-optimized Offline Library & Saved Tracks View for iPhone
public struct MobileLibraryView: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var model = MobileLibraryModel.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header & Segment Selector
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Library")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                // Segmented picker
                HStack(spacing: 8) {
                    ForEach(MobileLibrarySegment.allCases) { seg in
                        let isSelected = model.selectedSegment == seg
                        Button {
                            MobileHaptics.trigger(.selection)
                            withAnimation(FluidTheme.fluidSpring) {
                                model.selectedSegment = seg
                            }
                        } label: {
                            Text(seg.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                    
                    // Shuffle Play All Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        let tracks = currentTracks
                        if let first = tracks.shuffled().first {
                            MobileNavigationCoordinator.shared.revealMiniPlayer()
                            if model.selectedSegment == .downloaded {
                                player.playFromOfflineLibrary(tracks: tracks.shuffled(), selectedTrack: first)
                            } else {
                                player.playFromPlaylist(tracks: tracks.shuffled(), selectedTrack: first)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .bold))
                            Text("Shuffle")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                
                // Storage and song count badge for offline library
                if model.selectedSegment == .downloaded && !model.offlineTracks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(FluidTheme.downloadGreen)
                        Text("\(model.offlineTracks.count) \(model.offlineTracks.count == 1 ? "song" : "songs") • \(MediaCacheManager.shared.getFormattedCacheSize()) stored offline")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Clear All Downloads Button
                        Button {
                            MobileHaptics.trigger(.light)
                            model.showClearAllConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Clear All")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 6)
            
            // Track List
            Group {
                let tracks = currentTracks
                if tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: model.selectedSegment == .downloaded ? "arrow.down.circle" : "heart.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        
                        Text(model.selectedSegment == .downloaded ? "No Offline Tracks" : "No Favorites Yet")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        
                        Text(model.selectedSegment == .downloaded ? "Tracks downloaded in Sonorist will appear here for zero-data listening." : "Tap the heart on any song to save it to your favorites.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
                } else {
                    List {
                        ForEach(tracks, id: \.id) { track in
                            libraryTrackRow(for: track)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if model.selectedSegment == .downloaded || MediaCacheManager.shared.isCached(videoId: track.id) {
                                        Button(role: .destructive) {
                                            player.removeDownloadedTrack(track: track)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 180)
                    }
                }
            }
            .id(model.refreshID)
        }
        .onAppear {
            model.loadOfflineTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioPlayerEngine.trackDidCacheNotification)) { _ in
            model.loadOfflineTracks()
            model.refreshID = UUID()
        }
        .confirmationDialog(
            "Remove All Downloads?",
            isPresented: $model.showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Downloads (\(model.offlineTracks.count) songs)", role: .destructive) {
                MobileHaptics.trigger(.heavy)
                AudioPlayerEngine.shared.clearAllOfflineDownloads()
                model.loadOfflineTracks()
                model.refreshID = UUID()
                MobileToastManager.shared.show(message: "All Downloads Removed", icon: "trash")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(model.offlineTracks.count) downloaded songs and free \(MediaCacheManager.shared.getFormattedCacheSize()) of storage on your iPhone.")
        }
    }
    
    private var currentTracks: [Track] {
        switch model.selectedSegment {
        case .downloaded:
            return model.offlineTracks
        case .favorites:
            return player.likedTracks
        }
    }
    
    private func libraryTrackRow(for track: Track) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let isCached = model.selectedSegment == .downloaded || MediaCacheManager.shared.isCached(videoId: track.id)
        
        return HStack(spacing: 12) {
            // Main clickable playback area
            Button {
                MobileHaptics.trigger(.medium)
                MobileNavigationCoordinator.shared.revealMiniPlayer()
                if model.selectedSegment == .downloaded {
                    player.playFromOfflineLibrary(tracks: currentTracks, selectedTrack: track)
                } else {
                    player.playFromPlaylist(tracks: currentTracks, selectedTrack: track)
                }
            } label: {
                HStack(spacing: 12) {
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 10,
                        placeholderIconSize: 16
                    )
                    .frame(width: 48, height: 48)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isCurrent ? FluidTheme.musicRed : .primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            if isCached {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(FluidTheme.downloadGreen)
                            }
                            
                            Text(track.artist)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    if player.downloadingTrackIDs.contains(track.id) {
                        let progress = player.downloadProgress[track.id] ?? 0.05
                        HStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 2.2)
                                    .frame(width: 18, height: 18)
                                
                                Circle()
                                    .trim(from: 0, to: max(0.08, CGFloat(progress)))
                                    .stroke(FluidTheme.musicRed, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 18, height: 18)
                                    .animation(.easeInOut(duration: 0.15), value: progress)
                                
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(FluidTheme.musicRed)
                                    .frame(width: 5, height: 5)
                            }
                            
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(FluidTheme.musicRed)
                        }
                    } else {
                        Text(formatDuration(track.durationSeconds))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Isolated ellipsis menu (prevents conflicting gesture recognition)
            Menu {
                Button {
                    if model.selectedSegment == .downloaded {
                        player.playFromOfflineLibrary(tracks: currentTracks, selectedTrack: track)
                    } else {
                        player.playFromPlaylist(tracks: currentTracks, selectedTrack: track)
                    }
                } label: {
                    Label("Play Now", systemImage: "play.circle")
                }
                
                Button {
                    player.playNext(track: track)
                    MobileToastManager.shared.show(message: "Playing Next", icon: "arrow.up.and.down.and.sparkles")
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                
                Button {
                    player.addToQueue(track: track)
                    MobileToastManager.shared.show(message: "Added to Queue", icon: "text.badge.plus")
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
                
                // Per-song download removal or addition
                if isCached {
                    Button(role: .destructive) {
                        player.removeDownloadedTrack(track: track)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else if player.downloadingTrackIDs.contains(track.id) {
                    let progress = player.downloadProgress[track.id] ?? 0.05
                    Button {} label: {
                        Label("Downloading (\(Int(progress * 100))%)...", systemImage: "arrow.down.circle")
                    }
                    .disabled(true)
                } else {
                    Button {
                        player.downloadTrack(track: track)
                    } label: {
                        Label("Download Offline", systemImage: "arrow.down.circle")
                    }
                }
                
                Button {
                    let wasLiked = player.isLiked(track: track)
                    player.toggleLike(track: track)
                    MobileToastManager.shared.show(
                        message: wasLiked ? "Removed from Favorites" : "Added to Favorites",
                        icon: wasLiked ? "heart.slash" : "heart.fill"
                    )
                } label: {
                    Label(player.isLiked(track: track) ? "Favorited" : "Favorite",
                          systemImage: player.isLiked(track: track) ? "heart.fill" : "heart")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? FluidTheme.musicRed.opacity(0.08) : Color.clear)
        )
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
