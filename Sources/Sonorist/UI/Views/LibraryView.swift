import SwiftUI
import Combine

public enum LibraryTab: String, CaseIterable, Identifiable {
    case liked = "Liked Songs"
    case cached = "Offline Library"
    case history = "History"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .liked: return "heart.fill"
        case .cached: return "internaldrive.fill"
        case .history: return "clock.fill"
        }
    }
}

@MainActor
public final class LibraryViewModel: ObservableObject {
    public static let shared = LibraryViewModel()
    
    @Published public var selectedTab: LibraryTab = .liked
    @Published public var offlineTracks: [Track] = []
    @Published public var filterText: String = ""
    @Published public var formattedCacheSize: String = "0 KB"
    @Published public var showCacheClearedNotice: Bool = false
    @Published public var showClearCacheAlert: Bool = false
    @Published public var trackPendingDeletion: Track? = nil
    @Published public var showDeleteTrackAlert: Bool = false
    @Published public var exportStatusMessage: String? = nil
    
    public init() {}
    
    public func loadOfflineTracks() {
        self.offlineTracks = MediaCacheManager.shared.getAllCachedTracks()
        self.formattedCacheSize = MediaCacheManager.shared.getFormattedCacheSize()
    }
    
    public func removeTrackFromCache(track: Track) {
        MediaCacheManager.shared.removeCachedTrack(videoId: track.id)
        loadOfflineTracks()
    }
    
    public func clearCache() {
        MediaCacheManager.shared.clearCache()
        self.offlineTracks = []
        self.formattedCacheSize = MediaCacheManager.shared.getFormattedCacheSize()
        self.showCacheClearedNotice = true
    }
    
    public func exportAllTracksToFinder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Export All Songs to Folder"
        openPanel.prompt = "Choose Destination Folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        
        if openPanel.runModal() == .OK, let folderURL = openPanel.url {
            do {
                let count = try MediaCacheManager.shared.exportAllTracks(to: folderURL)
                self.exportStatusMessage = "Successfully exported \(count) songs to \(folderURL.lastPathComponent)!"
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            } catch {
                self.exportStatusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

public struct LibraryView: View {
    @ObservedObject var viewModel = LibraryViewModel.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool { colorScheme == .light }
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header & Storage Dashboard
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Library")
                            .font(FluidTheme.titleFont)
                        Text("Offline cached songs and listening history.")
                            .font(FluidTheme.captionFont)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minWidth: 0, alignment: .leading)
                    
                    Spacer(minLength: 8)
                    
                    HStack(spacing: 6) {
                        // Export All Songs to External Directory
                        Button(action: {
                            FluidHaptics.tap()
                            viewModel.exportAllTracksToFinder()
                        }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 25)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Export all offline tracks to standard .m4a files in Finder")
                        
                        // Reveal Parent Sonorist Folder
                        Button(action: {
                            FluidHaptics.tap()
                            MediaCacheManager.shared.revealParentFolderInFinder()
                        }) {
                            Label("Folder", systemImage: "folder")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 25)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Open the parent Sonorist folder in Finder")
                        
                        // Clear Library Action
                        Button(action: {
                            FluidHaptics.tap()
                            viewModel.showClearCacheAlert = true
                        }) {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FluidTheme.musicRed)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 25)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(FluidTheme.musicRed.opacity(0.25), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Purge offline compressed library to reclaim disk space")
                    }
                }
                
                // Apple Metric Cards Dashboard: Liked Songs, Offline Bundles, Disk Usage
                HStack(spacing: 8) {
                    metricCard(
                        icon: "heart.fill",
                        tint: FluidTheme.musicRed,
                        value: "\(player.likedTracks.count)",
                        label: "Liked Songs"
                    )
                    .frame(maxWidth: .infinity)
                    
                    metricCard(
                        icon: "arrow.down.circle.fill",
                        tint: Color.blue,
                        value: "\(viewModel.offlineTracks.count)",
                        label: "Offline Bundles"
                    )
                    .frame(maxWidth: .infinity)
                    
                    metricCard(
                        icon: "archivebox.fill",
                        tint: Color.purple,
                        value: viewModel.formattedCacheSize,
                        label: "Disk Storage"
                    )
                    .frame(maxWidth: .infinity)
                }
                
                // Notice when cleared
                if viewModel.showCacheClearedNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Cache successfully purged. All offline files removed (0 KB).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        Spacer()
                        Button("Dismiss") {
                            withAnimation { viewModel.showCacheClearedNotice = false }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Notice when exported
                if let exportMsg = viewModel.exportStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                        Text(exportMsg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                        Spacer()
                        Button("Dismiss") {
                            withAnimation { viewModel.exportStatusMessage = nil }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Tab Selector & Instant Offline Filter
            HStack(spacing: 8) {
                // Apple Segmented Control Bar
                HStack(spacing: 2) {
                    ForEach(LibraryTab.allCases) { tab in
                        Button(action: {
                            FluidHaptics.tap()
                            withAnimation(FluidTheme.tapSpring) {
                                viewModel.selectedTab = tab
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: viewModel.selectedTab == tab ? .bold : .medium, design: .rounded))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .foregroundColor(viewModel.selectedTab == tab ? .primary : .secondary)
                            .background(
                                viewModel.selectedTab == tab
                                    ? (isLight ? Color.white : Color.white.opacity(0.18))
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: viewModel.selectedTab == tab ? Color.black.opacity(0.08) : Color.clear, radius: 2, y: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                
                Spacer(minLength: 8)
                
                // In-Library Search Filter
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Filter...", text: $viewModel.filterText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11, design: .rounded))
                    
                    if !viewModel.filterText.isEmpty {
                        Button(action: {
                            FluidHaptics.tap()
                            viewModel.filterText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .frame(minWidth: 60, idealWidth: 110, maxWidth: 140)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            
            // Tab Content
            Group {
                switch viewModel.selectedTab {
                case .liked:
                    let tracks = filterTracks(player.likedTracks)
                    if tracks.isEmpty {
                        emptyState(
                            icon: "heart",
                            title: viewModel.filterText.isEmpty ? "No Liked Songs" : "No Matches Found",
                            subtitle: viewModel.filterText.isEmpty ? "Click the heart button on any song to save it to your favorites." : "No liked songs match '\(viewModel.filterText)'."
                        )
                    } else {
                        trackList(tracks: tracks)
                    }
                case .cached:
                    let tracks = filterTracks(viewModel.offlineTracks)
                    if tracks.isEmpty {
                        emptyState(
                            icon: "arrow.down.circle",
                            title: viewModel.filterText.isEmpty ? "No Offline Songs" : "No Matches Found",
                            subtitle: viewModel.filterText.isEmpty ? "Click the download arrow on any track to save it here for offline listening without an internet connection." : "No cached songs match '\(viewModel.filterText)'."
                        )
                    } else {
                        trackList(tracks: tracks)
                    }
                case .history:
                    let tracks = filterTracks(player.playHistory)
                    if tracks.isEmpty {
                        emptyState(
                            icon: "clock",
                            title: viewModel.filterText.isEmpty ? "No Listening History" : "No Matches Found",
                            subtitle: viewModel.filterText.isEmpty ? "Songs you play will automatically appear here." : "No history tracks match '\(viewModel.filterText)'."
                        )
                    } else {
                        trackList(tracks: tracks)
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            viewModel.loadOfflineTracks()
        }
        .alert("Clear Offline Cache?", isPresented: $viewModel.showClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.tapSpring) {
                    viewModel.clearCache()
                }
            }
        } message: {
            Text("This will remove all offline audio files (\(viewModel.formattedCacheSize)) from your Mac. You will need an active internet connection to stream these songs.")
        }
        .alert("Remove Download?", isPresented: $viewModel.showDeleteTrackAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.trackPendingDeletion = nil
            }
            Button("Remove Download", role: .destructive) {
                if let track = viewModel.trackPendingDeletion {
                    FluidHaptics.toggle()
                    withAnimation(FluidTheme.tapSpring) {
                        viewModel.removeTrackFromCache(track: track)
                    }
                }
                viewModel.trackPendingDeletion = nil
            }
        } message: {
            if let track = viewModel.trackPendingDeletion {
                Text("Remove \"\(track.title)\" from your offline storage? You will need an internet connection to stream this song.")
            } else {
                Text("Remove this song from your offline storage?")
            }
        }
    }
    
    private func filterTracks(_ tracks: [Track]) -> [Track] {
        guard !viewModel.filterText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return tracks
        }
        let q = viewModel.filterText.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q)
        }
    }
    
    @ViewBuilder
    private func metricCard(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 44)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundColor(.secondary.opacity(0.35))
            Text(title)
                .font(FluidTheme.headlineFont)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(FluidTheme.captionFont)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func trackList(tracks: [Track]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(tracks) { track in
                    TrackRowView(
                        track: track,
                        isCurrent: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying,
                        onRemoveDownload: {
                            viewModel.trackPendingDeletion = track
                            viewModel.showDeleteTrackAlert = true
                        },
                        onPlay: {
                            player.queue = tracks
                            player.play(track: track)
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
