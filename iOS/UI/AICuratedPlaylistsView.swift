import SwiftUI

// MARK: - Folder Customization Observable Manager

public final class FolderCustomizationManager: ObservableObject {
    public static let shared = FolderCustomizationManager()

    @Published public var isPresented: Bool = false
    @Published public var targetLanguage: String = ""
    @Published public var editingGenre: AIGenreGroup? = nil
    @Published public var isNew: Bool = false
    @Published public var folderName: String = "Spiritual"
    @Published public var folderDescription: String = "Devotional, spiritual, hymns, prayers, and Rabindra Sangeet"
    @Published public var selectedIcon: String = "sun.max.fill"

    public func presentNew(language: String) {
        self.targetLanguage = language
        self.editingGenre = nil
        self.isNew = true
        self.folderName = ""
        self.folderDescription = ""
        self.selectedIcon = "folder.fill"
        self.isPresented = true
    }

    public func presentEdit(language: String, genre: AIGenreGroup) {
        self.targetLanguage = language
        self.editingGenre = genre
        self.isNew = false
        self.folderName = genre.name
        self.folderDescription = genre.description
        self.selectedIcon = genre.icon
        self.isPresented = true
    }
}

// MARK: - Root Automated Playlists Folder View

public struct AICuratedPlaylistsFolderView: View {
    @ObservedObject private var engine = AIPlaylistEngine.shared
    @ObservedObject private var config = AIProviderConfig.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.platformSystemBackground
                    .ignoresSafeArea()

                if engine.curatedLibrary.categories.isEmpty && !engine.isCurating {
                    emptyOnboardingView
                } else {
                    folderListView
                }
            }
            .navigationTitle("Playlists")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Library")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    // Manual Refresh Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        engine.spinRefresh = true
                        Task {
                            await engine.curateEntireLibrary(force: true)
                            engine.spinRefresh = false
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FluidTheme.musicRed)
                            .rotationEffect(.degrees(engine.spinRefresh || engine.isCurating ? 360 : 0))
                            .animation(
                                engine.spinRefresh || engine.isCurating
                                    ? Animation.linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: engine.spinRefresh || engine.isCurating
                            )
                    }
                    .disabled(engine.isCurating)

                    // Quick Settings Shortcut
                    Button {
                        MobileHaptics.trigger(.light)
                        engine.showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                }
            }
            .sheet(isPresented: $engine.showingSettingsSheet) {
                AISettingsSheet()
            }
            .task {
                await engine.processPendingQueueIfNeeded()
            }
        }
    }

    // MARK: - Folder List View

    private var folderListView: some View {
        List {
            Section("Languages (\(engine.curatedLibrary.categories.count))") {
                ForEach(engine.curatedLibrary.categories) { category in
                    NavigationLink {
                        AILanguageDetailView(category: category)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(categoryColor(for: category.language).opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: category.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(categoryColor(for: category.language))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.language)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isLight ? .primary : .white)
                                
                                let genresSummary = category.genres.map { $0.name }.joined(separator: " • ")
                                Text(genresSummary)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("\(category.totalTrackCount)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                    )
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .refreshable {
            MobileHaptics.trigger(.medium)
            await engine.curateEntireLibrary(force: true)
        }
    }

    // MARK: - Zero-State Onboarding

    private var emptyOnboardingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(FluidTheme.musicRed.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "music.note.list")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
            }

            VStack(spacing: 6) {
                Text("No Playlists Yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(isLight ? .primary : .white)

                Text("Songs you download will automatically be organized here into genre and language collections.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                MobileHaptics.trigger(.medium)
                engine.showingSettingsSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(FluidTheme.musicRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FluidTheme.musicRed.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func categoryColor(for language: String) -> Color {
        switch language.lowercased() {
        case "hindi": return Color.orange
        case "bengali", "bangla": return Color.teal
        case "english": return Color.blue
        case "punjabi": return Color.yellow
        case "south indian", "tamil", "telugu", "malayalam", "kannada": return Color.green
        case "instrumental": return Color.purple
        default: return FluidTheme.musicRed
        }
    }
}

// MARK: - Language Detail View (With Custom Playlist Controls & Direct Songs)

public struct AILanguageDetailView: View {
    public let initialCategory: AILanguageCategory
    @ObservedObject private var engine = AIPlaylistEngine.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var manager = FolderCustomizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    public init(category: AILanguageCategory) {
        self.initialCategory = category
    }

    private var currentCategory: AILanguageCategory {
        engine.curatedLibrary.categories.first(where: {
            $0.language.caseInsensitiveCompare(initialCategory.language) == .orderedSame
        }) ?? initialCategory
    }

    private var allTracks: [Track] {
        let allCached = MediaCacheManager.shared.getAllCachedTracks()
        let idSet = Set(currentCategory.directTrackIds + currentCategory.genres.flatMap { $0.trackIds })
        return allCached.filter { idSet.contains($0.id) }
    }

    private var directTracks: [Track] {
        let allCached = MediaCacheManager.shared.getAllCachedTracks()
        let idSet = Set(currentCategory.directTrackIds)
        return allCached.filter { idSet.contains($0.id) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Subheader: song count with Shuffle button
            HStack {
                Text("\(allTracks.count) \(allTracks.count == 1 ? "song" : "songs")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if !allTracks.isEmpty {
                    Button {
                        MobileHaptics.trigger(.medium)
                        let tracks = allTracks.shuffled()
                        if let first = tracks.first {
                            MobileNavigationCoordinator.shared.revealMiniPlayer()
                            player.playFromOfflineLibrary(tracks: tracks, selectedTrack: first)
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
                        .padding(.vertical, 6)
                        .background(FluidTheme.musicRed.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)

            // Main List: Add Folder on top, followed by user-created folders, followed by songs
            List {
                // 1. "Add Playlist Folder" row right at the top
                addPlaylistFolderRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                // 2. User-created folders in this language (styled like playlistsFolderRow in Library)
                if !currentCategory.genres.isEmpty {
                    ForEach(currentCategory.genres) { subfolder in
                        userFolderRow(for: subfolder)
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    manager.presentEdit(language: currentCategory.language, genre: subfolder)
                                } label: {
                                    Label("Customize", systemImage: "slider.horizontal.3")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    engine.deleteGenre(in: currentCategory.language, name: subfolder.name)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    manager.presentEdit(language: currentCategory.language, genre: subfolder)
                                } label: {
                                    Label("Customize Folder...", systemImage: "slider.horizontal.3")
                                }

                                Button(role: .destructive) {
                                    engine.deleteGenre(in: currentCategory.language, name: subfolder.name)
                                } label: {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }
                    }
                }

                // 3. All songs laying below (unidentified or not in a subfolder)
                if directTracks.isEmpty && currentCategory.genres.isEmpty {
                    Text("No downloaded songs in \(currentCategory.language) yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(directTracks) { track in
                        languageTrackRow(for: track)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading) {
                                if !currentCategory.genres.isEmpty {
                                    Menu {
                                        ForEach(currentCategory.genres) { targetSubfolder in
                                            Button {
                                                MobileHaptics.trigger(.medium)
                                                engine.moveTrack(
                                                    trackId: track.id,
                                                    in: currentCategory.language,
                                                    fromGenre: "root",
                                                    toGenre: targetSubfolder.name
                                                )
                                            } label: {
                                                Label(targetSubfolder.name, systemImage: targetSubfolder.icon)
                                            }
                                        }
                                    } label: {
                                        Label("Move", systemImage: "folder")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .contextMenu {
                                Button {
                                    MobileHaptics.trigger(.medium)
                                    player.addToQueue(track: track)
                                } label: {
                                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                }

                                if !currentCategory.genres.isEmpty {
                                    Menu {
                                        ForEach(currentCategory.genres) { targetSubfolder in
                                            Button {
                                                MobileHaptics.trigger(.medium)
                                                engine.moveTrack(
                                                    trackId: track.id,
                                                    in: currentCategory.language,
                                                    fromGenre: "root",
                                                    toGenre: targetSubfolder.name
                                                )
                                            } label: {
                                                Label(targetSubfolder.name, systemImage: targetSubfolder.icon)
                                            }
                                        }
                                    } label: {
                                        Label("Move to Folder...", systemImage: "folder")
                                    }
                                }

                                Button {
                                    manager.presentNew(language: currentCategory.language)
                                } label: {
                                    Label("New Folder...", systemImage: "folder.badge.plus")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(currentCategory.language)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $manager.isPresented) {
            AICustomizeFolderSheet()
        }
    }

    // MARK: - Add Playlist Folder Row (Always on top)

    private var addPlaylistFolderRow: some View {
        Button {
            MobileHaptics.trigger(.medium)
            manager.presentNew(language: currentCategory.language)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FluidTheme.musicRed.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(FluidTheme.musicRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Playlist Folder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(FluidTheme.musicRed)

                    Text("Create a folder (e.g. Spiritual, Party)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - User-Created Subfolder Row (Identical to Library's Playlists row)

    private func userFolderRow(for subfolder: AIGenreGroup) -> some View {
        NavigationLink {
            AIGenreTrackListView(language: currentCategory.language, genre: subfolder)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(categoryColor(for: currentCategory.language).opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: subfolder.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(categoryColor(for: currentCategory.language))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(subfolder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isLight ? .primary : .white)

                    let count = subfolder.trackIds.count
                    Text("\(count) \(count == 1 ? "song" : "songs")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Song Row (Matches Library Track Row)

    private func languageTrackRow(for track: Track) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let isCached = MediaCacheManager.shared.isCached(videoId: track.id)

        return HStack(spacing: 12) {
            Button {
                MobileHaptics.trigger(.medium)
                MobileNavigationCoordinator.shared.revealMiniPlayer()
                player.playFromOfflineLibrary(tracks: directTracks, selectedTrack: track)
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
                            .foregroundColor(isCurrent ? FluidTheme.musicRed : (isLight ? .primary : .white))
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
                }
            }
            .buttonStyle(PlainButtonStyle())

            Menu {
                Button {
                    MobileHaptics.trigger(.light)
                    player.addToQueue(track: track)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                if !currentCategory.genres.isEmpty {
                    Menu {
                        ForEach(currentCategory.genres) { targetSubfolder in
                            Button {
                                MobileHaptics.trigger(.medium)
                                engine.moveTrack(
                                    trackId: track.id,
                                    in: currentCategory.language,
                                    fromGenre: "root",
                                    toGenre: targetSubfolder.name
                                )
                            } label: {
                                Label(targetSubfolder.name, systemImage: targetSubfolder.icon)
                            }
                        }
                    } label: {
                        Label("Move to Folder...", systemImage: "folder")
                    }
                }

                Button {
                    manager.presentNew(language: currentCategory.language)
                } label: {
                    Label("New Folder...", systemImage: "folder.badge.plus")
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

    private func categoryColor(for language: String) -> Color {
        switch language.lowercased() {
        case "hindi": return Color.orange
        case "bengali", "bangla": return Color.teal
        case "english": return Color.blue
        case "punjabi": return Color.yellow
        case "south indian", "tamil", "telugu", "malayalam", "kannada": return Color.green
        case "instrumental": return Color.purple
        default: return FluidTheme.musicRed
        }
    }
}

// Color amber compatibility
private extension Color {
    static var amber: Color { Color(red: 0.95, green: 0.65, blue: 0.1) }
}

// MARK: - Folder Customization Sheet

public struct AICustomizeFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var manager = FolderCustomizationManager.shared
    @ObservedObject private var engine = AIPlaylistEngine.shared

    private var isLight: Bool { colorScheme == .light }

    private let availableIcons = [
        "sun.max.fill", "sparkles", "hands.sparkles.fill", "heart.fill",
        "flame.fill", "moon.stars.fill", "bolt.fill", "guitars",
        "music.mic", "music.note", "star.fill", "leaf.fill", "cross.fill"
    ]

    private let presets: [(name: String, icon: String, description: String)] = [
        ("Spiritual", "sun.max.fill", "Devotional, spiritual, hymns, prayers, and Rabindra Sangeet"),
        ("Rabindra Sangeet", "sparkles", "Timeless Bengali songs and poetry of Rabindranath Tagore"),
        ("Classics & Heritage", "sparkles", "Golden era classics and timeless favorites"),
        ("Acoustic & Chill", "moon.stars.fill", "Gentle acoustic, lo-fi, and midnight vibes"),
        ("Pop & Dance", "flame.fill", "High-energy chart-toppers and dance beats"),
        ("Sufi & Ghazal", "moon.stars.fill", "Soulful Sufi poetry, ghazals, and meditative ragas")
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Live Visual Preview Card
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(FluidTheme.musicRed.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: manager.selectedIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(FluidTheme.musicRed)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(manager.folderName.isEmpty ? "Folder Name" : manager.folderName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isLight ? .primary : .white)

                            Text(manager.folderDescription.isEmpty ? "Tap a preset below or type description" : manager.folderDescription)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Folder Preview")
                }

                // Name & Context
                Section("Folder Details") {
                    TextField("Folder Name (e.g. Spiritual)", text: $manager.folderName)
                        .font(.system(size: 15))

                    TextField("Description / Genre Context", text: $manager.folderDescription)
                        .font(.system(size: 13))
                }

                // Quick Presets
                Section("Quick Presets") {
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            MobileHaptics.trigger(.light)
                            manager.folderName = preset.name
                            manager.selectedIcon = preset.icon
                            manager.folderDescription = preset.description
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FluidTheme.musicRed)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(isLight ? .primary : .white)
                                    Text(preset.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Icon Selection
                Section("Folder Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    MobileHaptics.trigger(.light)
                                    manager.selectedIcon = icon
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(manager.selectedIcon == icon ? FluidTheme.musicRed : Color.primary.opacity(0.06))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: icon)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(manager.selectedIcon == icon ? .white : (isLight ? .primary : .white))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // Permanence Note
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("This folder is permanent and will stay even if empty. AI curation will automatically route matching songs into it.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle(manager.isNew ? "New Folder" : "Customize Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        manager.isPresented = false
                    }
                    .foregroundColor(FluidTheme.musicRed)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MobileHaptics.trigger(.medium)
                        saveFolder()
                        manager.isPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
                    .disabled(manager.folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveFolder() {
        let cleanName = manager.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if manager.isNew || manager.editingGenre == nil {
            engine.addCustomGenre(
                in: manager.targetLanguage,
                name: cleanName,
                icon: manager.selectedIcon,
                description: manager.folderDescription
            )
            Task {
                await engine.syncLanguageFolder(
                    language: manager.targetLanguage,
                    newSubfolderName: cleanName
                )
            }
        } else if let eg = manager.editingGenre {
            engine.renameGenre(
                in: manager.targetLanguage,
                oldName: eg.name,
                newName: cleanName,
                newIcon: manager.selectedIcon,
                newDescription: manager.folderDescription
            )
        }
    }
}

// MARK: - Genre Track List View

public struct AIGenreTrackListView: View {
    public let language: String
    public let initialGenre: AIGenreGroup
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var engine = AIPlaylistEngine.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    private var currentCategory: AILanguageCategory? {
        engine.curatedLibrary.categories.first(where: {
            $0.language.caseInsensitiveCompare(language) == .orderedSame
        })
    }

    private var currentGenre: AIGenreGroup {
        currentCategory?.genres.first(where: {
            $0.name.caseInsensitiveCompare(initialGenre.name) == .orderedSame
        }) ?? initialGenre
    }

    private var otherGenres: [AIGenreGroup] {
        (currentCategory?.genres ?? []).filter {
            $0.name.caseInsensitiveCompare(currentGenre.name) != .orderedSame
        }
    }

    private var tracks: [Track] {
        let allCached = MediaCacheManager.shared.getAllCachedTracks()
        let idSet = Set(currentGenre.trackIds)
        return allCached.filter { idSet.contains($0.id) }
    }

    public init(language: String, genre: AIGenreGroup) {
        self.language = language
        self.initialGenre = genre
    }

    public var body: some View {
        List {
            // Hero Header
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(FluidTheme.musicRed.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: currentGenre.icon)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(FluidTheme.musicRed)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentGenre.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(isLight ? .primary : .white)
                            Text("\(language) • \(tracks.count) Songs")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Play All & Shuffle Buttons
                    HStack(spacing: 10) {
                        Button {
                            if let first = tracks.first {
                                MobileHaptics.trigger(.medium)
                                MobileNavigationCoordinator.shared.revealMiniPlayer()
                                player.playFromOfflineLibrary(tracks: tracks, selectedTrack: first)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(FluidTheme.musicRed)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button {
                            if let first = tracks.shuffled().first {
                                MobileHaptics.trigger(.medium)
                                MobileNavigationCoordinator.shared.revealMiniPlayer()
                                player.playFromOfflineLibrary(tracks: tracks.shuffled(), selectedTrack: first)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isLight ? .primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                )
            }

            // Track Rows
            Section {
                ForEach(tracks) { track in
                    Button {
                        MobileHaptics.trigger(.light)
                        MobileNavigationCoordinator.shared.revealMiniPlayer()
                        player.playFromOfflineLibrary(tracks: tracks, selectedTrack: track)
                    } label: {
                        HStack(spacing: 12) {
                            TrackArtworkView(
                                url: track.artworkURL,
                                cornerRadius: 8
                            )
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(player.currentTrack?.id == track.id ? FluidTheme.musicRed : (isLight ? .primary : .white))
                                    .lineLimit(1)

                                Text(track.artist)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                    )
                    .swipeActions(edge: .leading) {
                        Menu {
                            Button {
                                MobileHaptics.trigger(.medium)
                                engine.moveTrack(
                                    trackId: track.id,
                                    in: language,
                                    fromGenre: currentGenre.name,
                                    toGenre: "root"
                                )
                            } label: {
                                Label("Move to Main Folder", systemImage: "arrow.uturn.backward")
                            }

                            ForEach(otherGenres) { dest in
                                Button {
                                    MobileHaptics.trigger(.medium)
                                    engine.moveTrack(
                                        trackId: track.id,
                                        in: language,
                                        fromGenre: currentGenre.name,
                                        toGenre: dest.name
                                    )
                                } label: {
                                    Label("Move to \(dest.name)", systemImage: dest.icon)
                                }
                            }
                        } label: {
                            Label("Move", systemImage: "folder")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            MobileHaptics.trigger(.medium)
                            engine.moveTrack(
                                trackId: track.id,
                                in: language,
                                fromGenre: currentGenre.name,
                                toGenre: "root"
                            )
                        } label: {
                            Label("Move to Main Folder", systemImage: "arrow.uturn.backward")
                        }

                        if !otherGenres.isEmpty {
                            Menu {
                                ForEach(otherGenres) { dest in
                                    Button {
                                        MobileHaptics.trigger(.medium)
                                        engine.moveTrack(
                                            trackId: track.id,
                                            in: language,
                                            fromGenre: currentGenre.name,
                                            toGenre: dest.name
                                        )
                                    } label: {
                                        Label(dest.name, systemImage: dest.icon)
                                    }
                                }
                            } label: {
                                Label("Move to Other Subfolder...", systemImage: "folder")
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .refreshable {
            MobileHaptics.trigger(.medium)
            await AIPlaylistEngine.shared.curateEntireLibrary(force: true)
        }
        .navigationTitle(currentGenre.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - AI Settings Sheet

public struct AISettingsSheet: View {
    @ObservedObject private var config = AIProviderConfig.shared
    @ObservedObject private var engine = AIPlaylistEngine.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // OpenRouter AI Engine
                Section {
                    SecureField("OpenRouter API Key", text: $config.apiKey)
                        .font(.system(size: 14, design: .monospaced))

                    if let url = URL(string: config.selectedProvider.instructionsURL) {
                        HStack {
                            Link("Get Free OpenRouter Key ↗", destination: url)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(FluidTheme.musicRed)
                            Spacer()
                        }
                    }

                    // Model Selection Dropdown (Picker)
                    Picker("Free AI Model", selection: $config.selectedModelId) {
                        ForEach(config.availableFreeModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(FluidTheme.musicRed)
                            .font(.system(size: 11))
                        Text("100% Free • Filtered for zero-cost music classification.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)

                    // Test Connection & Refresh Models Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        Task {
                            _ = await engine.testAPIConnection()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if engine.testingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                            }
                            Text(engine.testingConnection ? "Verifying & Fetching Models..." : "Test Key & Refresh Free Models")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                    }
                    .disabled(engine.testingConnection || config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let msg = engine.connectionMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: msg.hasPrefix("✓") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                            Text(msg)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("OpenRouter AI Engine")
                } footer: {
                    Text("Enter your free key, then select from verified free models in the dropdown above.")
                }

                // Folder Customization Presets
                Section("Playlist Customization") {
                    Button {
                        MobileHaptics.trigger(.medium)
                        engine.applyGlobalClassicsPreference(useSpiritual: true)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use 'Spiritual' Folder Across Languages")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isLight ? .primary : .white)
                                Text("Replaces 'Classics & Heritage' with 'Spiritual' so Rabindra Sangeet, bhajans, and hymns go into their own folder.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        MobileHaptics.trigger(.medium)
                        engine.applyGlobalClassicsPreference(useSpiritual: false)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset to 'Classics & Heritage'")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isLight ? .primary : .white)
                                Text("Restores standard golden era classics title.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Automation Toggles
                Section("Automation") {
                    Toggle(isOn: $config.isAutoCurateOnDownloadEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Organize Downloads")
                                .font(.system(size: 14, weight: .medium))
                            Text("Immediately organizes songs into language & genre folders upon download.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(FluidTheme.musicRed)

                    Toggle(isOn: $config.isAutoRetryPendingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event-Driven Queue Processing")
                                .font(.system(size: 14, weight: .medium))
                            Text("Retries pending tracks when internet restores.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(FluidTheme.musicRed)
                }

                // Manual Full Library Curation Action
                Section {
                    Button {
                        MobileHaptics.trigger(.medium)
                        Task {
                            await engine.curateEntireLibrary(force: true)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if engine.isCurating {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 6)
                            }
                            Text(engine.isCurating ? "Organizing Music Library..." : "Curate Library Now")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(FluidTheme.musicRed)
                            Spacer()
                        }
                    }
                    .disabled(engine.isCurating)
                } footer: {
                    if let err = engine.lastSyncError {
                        Text("Notice: \(err)")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    } else if let last = config.lastSyncDate {
                        Text("Last organized: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Playlist Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
    }
}
