import SwiftUI

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
            // Language Folders

            // Language Folders
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

// MARK: - Language Detail View (Max 5 Genres)

public struct AILanguageDetailView: View {
    public let category: AILanguageCategory
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    public init(category: AILanguageCategory) {
        self.category = category
    }

    public var body: some View {
        List {
            Section {
                ForEach(category.genres) { genre in
                    NavigationLink {
                        AIGenreTrackListView(language: category.language, genre: genre)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(genreColor(for: genre.name).opacity(0.15))
                                    .frame(width: 42, height: 42)
                                Image(systemName: genre.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(genreColor(for: genre.name))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(genre.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isLight ? .primary : .white)
                                if !genre.description.isEmpty {
                                    Text(genre.description)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text("\(genre.trackIds.count)")
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
            } header: {
                Text("\(category.language) Genres (Max 5)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
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
        .navigationTitle(category.language)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func genreColor(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("pop") || n.contains("dance") { return Color.pink }
        if n.contains("romance") || n.contains("melod") { return Color.red }
        if n.contains("chill") || n.contains("acoustic") { return Color.indigo }
        if n.contains("classic") || n.contains("heritage") { return Color.amber }
        if n.contains("energetic") || n.contains("rap") { return Color.orange }
        return FluidTheme.musicRed
    }
}

// Color amber compatibility
private extension Color {
    static var amber: Color { Color(red: 0.95, green: 0.65, blue: 0.1) }
}

// MARK: - Genre Track List View

public struct AIGenreTrackListView: View {
    public let language: String
    public let genre: AIGenreGroup
    @ObservedObject private var player = AudioPlayerEngine.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    private var tracks: [Track] {
        let allCached = MediaCacheManager.shared.getAllCachedTracks()
        let idSet = Set(genre.trackIds)
        return allCached.filter { idSet.contains($0.id) }
    }

    public init(language: String, genre: AIGenreGroup) {
        self.language = language
        self.genre = genre
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
                            Image(systemName: genre.icon)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(FluidTheme.musicRed)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(genre.name)
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
        .navigationTitle(genre.name)
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
                // Provider Selection
                Section("Provider") {
                    Picker("Provider", selection: $config.selectedProvider) {
                        ForEach(AIProvider.allCases) { prov in
                            Text(prov.displayName).tag(prov)
                        }
                    }
                    .pickerStyle(.menu)

                    if config.selectedProvider.requiresApiKey {
                        SecureField("API Key", text: $config.apiKey)
                            .font(.system(size: 14, design: .monospaced))

                        if !config.selectedProvider.instructionsURL.isEmpty,
                           let url = URL(string: config.selectedProvider.instructionsURL) {
                            HStack {
                                Link("Get Free \(config.selectedProvider.shortName) Key ↗", destination: url)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FluidTheme.musicRed)
                                Spacer()
                            }
                        }
                    } else if config.selectedProvider == .ollama {
                        TextField("Endpoint URL", text: $config.customEndpoint, prompt: Text("http://localhost:11434/v1/chat/completions"))
                            .font(.system(size: 13, design: .monospaced))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 13))
                            Text("No sign-up or API key required. Works automatically.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Test Connection Button
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
                            Text(engine.testingConnection ? "Verifying with \(config.selectedProvider.displayName)..." : (config.selectedProvider.requiresApiKey ? "Test API Key & Verify Connection" : "Test Connection"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                    }
                    .disabled(engine.testingConnection || (config.selectedProvider.requiresApiKey && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

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
                }

                // Automation Toggles
                Section("Playlists") {
                    Toggle("Organize on Download", isOn: $config.isAutoCurateOnDownloadEnabled)
                        .tint(FluidTheme.musicRed)
                    Text("Automatically adds new songs to genre folders when downloaded.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Toggle("Auto-Sync Pending Tracks", isOn: $config.isAutoRetryPendingEnabled)
                        .tint(FluidTheme.musicRed)
                    Text("Retries pending tracks from the outbox log automatically when connected to internet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Outbox Sync Queue Section
                Section("Outbox Sync Queue") {
                    HStack {
                        Text("Queue Status")
                        Spacer()
                        if engine.pendingQueue.isEmpty {
                            Text("Clean (0 pending)")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(engine.pendingQueue.count) pending sync")
                                .foregroundColor(FluidTheme.musicRed)
                                .fontWeight(.medium)
                        }
                    }

                    if !engine.pendingQueue.isEmpty {
                        Button {
                            MobileHaptics.trigger(.medium)
                            Task {
                                await engine.processPendingQueueIfNeeded()
                            }
                        } label: {
                            HStack {
                                if engine.isProcessingPendingQueue {
                                    ProgressView()
                                        .padding(.trailing, 6)
                                }
                                Text("Sync Pending Tracks Now")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FluidTheme.musicRed)
                            }
                        }
                        .disabled(engine.isProcessingPendingQueue)
                    }
                }

                // Re-Analyze Action
                Section {
                    Button {
                        MobileHaptics.trigger(.medium)
                        Task {
                            await engine.curateEntireLibrary(force: true)
                        }
                    } label: {
                        HStack {
                            if engine.isCurating {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(engine.isCurating ? "Organizing Songs..." : "Re-Organize Offline Library")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                    }
                    .disabled(engine.isCurating || engine.testingConnection)

                    Text("Re-classifies all downloaded songs into language and genre playlists.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
