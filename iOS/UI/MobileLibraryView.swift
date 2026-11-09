import SwiftUI

public final class MobileLibraryModel: ObservableObject {
    public static let shared = MobileLibraryModel()
    @Published public var selectedSegment: MobileLibrarySegment = .downloaded
    @Published public var showSettings: Bool = false
    @Published public var showClearAllConfirmation: Bool = false
    @Published public var refreshID: UUID = UUID()
    @Published public var offlineTracks: [Track] = []
    @Published public var navigateToPlaylists: Bool = false
    
    // Batch Selection Mode
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedTrackIds: Set<String> = []
    @Published public var showBatchDeleteConfirmation: Bool = false
    
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
    
    public func toggleTrackSelection(id: String) {
        if selectedTrackIds.contains(id) {
            selectedTrackIds.remove(id)
        } else {
            selectedTrackIds.insert(id)
        }
    }
    
    public func selectAll(tracks: [Track]) {
        selectedTrackIds = Set(tracks.map { $0.id })
    }
    
    public func deselectAll() {
        selectedTrackIds.removeAll()
    }
    
    public func exitSelectionMode() {
        isSelectionMode = false
        selectedTrackIds.removeAll()
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
    @ObservedObject private var themeManager = AppThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool { colorScheme == .light }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Header (Pinned comfortably below Dynamic Island / status bar, identical to Search & Insights)
                    headerSection
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    // Segment Selector (Downloaded / Favorites) & Storage Badge
                    segmentSelectorSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    // Content List
                    List {
                        // Playlists Folder Row (When on Downloaded segment and not in selection mode)
                        if model.selectedSegment == .downloaded && !model.isSelectionMode {
                            playlistsFolderRow
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        // Tracks or Empty State
                        let tracks = currentTracks
                        if tracks.isEmpty {
                            emptyStateView
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(tracks, id: \.id) { track in
                                libraryTrackRow(for: track)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if !model.isSelectionMode && (model.selectedSegment == .downloaded || MediaCacheManager.shared.isCached(videoId: track.id)) {
                                            Button(role: .destructive) {
                                                player.removeDownloadedTrack(track: track)
                                                model.loadOfflineTracks()
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: model.isSelectionMode ? 220 : 180)
                    }
                    .refreshable {
                        MobileHaptics.trigger(.medium)
                        model.loadOfflineTracks()
                        await AIPlaylistEngine.shared.reconcileWithCachedTracks()
                    }
                    .id(model.refreshID)
                }

                // Floating Batch Selection Toolbar (visible when selecting songs)
                if model.isSelectionMode {
                    batchSelectionToolbar
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .background(Color.platformSystemBackground.ignoresSafeArea())
        }
        .onAppear {
            model.loadOfflineTracks()
            AIPlaylistEngine.shared.reconcileWithCachedTracks()
        }
        .onDisappear {
            model.exitSelectionMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioPlayerEngine.trackDidCacheNotification)) { _ in
            model.loadOfflineTracks()
            model.refreshID = UUID()
        }
        .sheet(isPresented: $model.showSettings) {
            MobileSettingsView(isPresentedAsSheet: true)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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
        .confirmationDialog(
            batchDeleteTitle,
            isPresented: $model.showBatchDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(batchDeleteConfirmLabel, role: .destructive) {
                deleteSelectedTracks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(batchDeleteMessage)
        }
    }

    // MARK: - Header (Clean, Pinned, Theme Switcher & Settings)

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            if model.isSelectionMode {
                // Done button to exit selection mode
                Button {
                    MobileHaptics.trigger(.light)
                    withAnimation(FluidTheme.fluidSpring) {
                        model.exitSelectionMode()
                    }
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                }

                Spacer()

                Text("\(model.selectedTrackIds.count) Selected")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                let allSelected = !currentTracks.isEmpty && model.selectedTrackIds.count == currentTracks.count
                Button {
                    MobileHaptics.trigger(.selection)
                    withAnimation(FluidTheme.fluidSpring) {
                        if allSelected {
                            model.deselectAll()
                        } else {
                            model.selectAll(tracks: currentTracks)
                        }
                    }
                } label: {
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FluidTheme.musicRed)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Library")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Offline downloads & favorites")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()

                // Multi-select Trigger Button
                if !currentTracks.isEmpty {
                    Button {
                        MobileHaptics.trigger(.selection)
                        withAnimation(FluidTheme.fluidSpring) {
                            model.isSelectionMode = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Select")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(FluidTheme.musicRed.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Theme Appearance Switcher Menu
                Menu {
                    ForEach(AppThemeMode.allCases) { mode in
                        Button {
                            themeManager.setTheme(mode)
                        } label: {
                            Label(mode.displayName, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: themeManager.currentTheme.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }

                // Settings Button
                Button {
                    MobileHaptics.trigger(.selection)
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: model.selectedSegment == .downloaded ? "arrow.down.circle" : "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(model.selectedSegment == .downloaded ? "No Offline Tracks" : "No Favorites Yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            
            Text(model.selectedSegment == .downloaded ? "Tracks downloaded in Sonorist will appear here for zero-data listening." : "Tap the heart on any song to save it to your favorites.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Segment Selector & Controls Section (Clean native scrollable header)

    private var segmentSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Segmented picker
            HStack(spacing: 8) {
                ForEach(MobileLibrarySegment.allCases) { seg in
                    let isSelected = model.selectedSegment == seg
                    Button {
                        MobileHaptics.trigger(.selection)
                        withAnimation(FluidTheme.fluidSpring) {
                            model.selectedSegment = seg
                            model.exitSelectionMode()
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
                
                if !model.isSelectionMode {
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
            }
            
            // Storage and song count badge for offline library
            if model.selectedSegment == .downloaded && !model.offlineTracks.isEmpty && !model.isSelectionMode {
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
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
    
    private var playlistsFolderRow: some View {
        Button {
            MobileHaptics.trigger(.light)
            model.navigateToPlaylists = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FluidTheme.musicRed.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(FluidTheme.musicRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Playlists")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isLight ? .primary : .white)

                    let total = AIPlaylistEngine.shared.curatedLibrary.totalTrackCount
                    let catCount = AIPlaylistEngine.shared.curatedLibrary.categories.count
                    if total > 0 {
                        Text("\(total) \(total == 1 ? "song" : "songs") • \(catCount) \(catCount == 1 ? "category" : "categories")")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Organized by language & genre")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .navigationDestination(isPresented: $model.navigateToPlaylists) {
            AICuratedPlaylistsFolderView()
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
        let isSelected = model.selectedTrackIds.contains(track.id)
        
        return HStack(spacing: 12) {
            // Checkbox when in multi-selection mode
            if model.isSelectionMode {
                Button {
                    MobileHaptics.trigger(.selection)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.toggleTrackSelection(id: track.id)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? FluidTheme.musicRed : .secondary.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }

            // Main clickable playback / selection area
            Button {
                if model.isSelectionMode {
                    MobileHaptics.trigger(.selection)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.toggleTrackSelection(id: track.id)
                    }
                } else {
                    MobileHaptics.trigger(.medium)
                    MobileNavigationCoordinator.shared.revealMiniPlayer()
                    if model.selectedSegment == .downloaded {
                        player.playFromOfflineLibrary(tracks: currentTracks, selectedTrack: track)
                    } else {
                        player.playFromPlaylist(tracks: currentTracks, selectedTrack: track)
                    }
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
            
            // Isolated ellipsis menu (only shown when NOT in selection mode)
            if !model.isSelectionMode {
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
                            model.loadOfflineTracks()
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? FluidTheme.musicRed.opacity(0.12) : (isCurrent ? FluidTheme.musicRed.opacity(0.08) : Color.clear))
        )
        // Long press anywhere on the song row triggers selection mode and checks this song
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                if !model.isSelectionMode {
                    MobileHaptics.trigger(.heavy)
                    withAnimation(FluidTheme.fluidSpring) {
                        model.isSelectionMode = true
                        model.selectedTrackIds = [track.id]
                    }
                }
            }
        )
    }

    // MARK: - Floating Batch Selection Toolbar

    private var batchSelectionToolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selectedTrackIds.count) of \(currentTracks.count) selected")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                if model.selectedSegment == .downloaded {
                    let totalBytes = calculateSelectedTracksSize(ids: model.selectedTrackIds)
                    Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) + " to free up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text(model.selectedSegment.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Delete Selected Button
            Button {
                MobileHaptics.trigger(.medium)
                model.showBatchDeleteConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.selectedTrackIds.count == currentTracks.count && !currentTracks.isEmpty ? "Delete All" : "Delete (\(model.selectedTrackIds.count))")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(model.selectedTrackIds.isEmpty ? Color.gray.opacity(0.4) : FluidTheme.musicRed)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.selectedTrackIds.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 96) // Floats comfortably above bottom tab bar dock
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Batch Deletion Logic

    private func deleteSelectedTracks() {
        let idsToDelete = model.selectedTrackIds
        guard !idsToDelete.isEmpty else { return }
        let tracksToDelete = currentTracks.filter { idsToDelete.contains($0.id) }
        let count = tracksToDelete.count
        
        MobileHaptics.trigger(.heavy)
        
        if model.selectedSegment == .downloaded {
            for track in tracksToDelete {
                player.removeDownloadedTrack(track: track)
            }
            model.loadOfflineTracks()
            Task {
                await AIPlaylistEngine.shared.reconcileWithCachedTracks()
            }
        } else {
            player.likedTracks.removeAll { idsToDelete.contains($0.id) }
            player.saveLikedTracks()
        }
        
        model.exitSelectionMode()
        model.refreshID = UUID()
        MobileToastManager.shared.show(
            message: "Removed \(count) \(count == 1 ? "song" : "songs")",
            icon: "trash"
        )
    }

    private func calculateSelectedTracksSize(ids: Set<String>) -> Int64 {
        let cache = MediaCacheManager.shared
        var total: Int64 = 0
        for id in ids {
            let file = cache.libraryDirectory.appendingPathComponent("\(id).sonorist")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    private var batchDeleteTitle: String {
        let count = model.selectedTrackIds.count
        let type = model.selectedSegment == .downloaded ? "Downloads" : "Favorites"
        return count == currentTracks.count && !currentTracks.isEmpty ? "Delete All \(type)?" : "Delete \(count) \(type)?"
    }

    private var batchDeleteConfirmLabel: String {
        let count = model.selectedTrackIds.count
        return count == currentTracks.count && !currentTracks.isEmpty ? "Delete All (\(count) Songs)" : "Delete \(count) \(count == 1 ? "Song" : "Songs")"
    }

    private var batchDeleteMessage: String {
        let count = model.selectedTrackIds.count
        if model.selectedSegment == .downloaded {
            let size = ByteCountFormatter.string(fromByteCount: calculateSelectedTracksSize(ids: model.selectedTrackIds), countStyle: .file)
            return "This will permanently remove the \(count) selected \(count == 1 ? "song" : "songs") from offline storage and free up \(size) on your iPhone."
        } else {
            return "This will remove the \(count) selected \(count == 1 ? "song" : "songs") from your Favorites list."
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
