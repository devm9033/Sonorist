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
            .navigationTitle("Automated Playlists")
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
                await engine.performDailySyncIfNeeded()
            }
        }
    }

    // MARK: - Folder List View

    private var folderListView: some View {
        List {
            // Automation Status Card
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(FluidTheme.musicRed.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("AI Auto-Curation")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isLight ? .primary : .white)
                            Text("Active")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if let lastSync = config.lastSyncDate {
                            Text("Last organized \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Songs automatically categorized on download")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
                )
            }

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
    }

    // MARK: - Zero-State Onboarding

    private var emptyOnboardingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FluidTheme.musicRed.opacity(0.25), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FluidTheme.musicRed, Color.pink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Curate Your Music with AI")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isLight ? .primary : .white)

                Text("Automatically organize all your offline downloaded songs into language and genre folders.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Steps Card
            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: "1", title: "Add Your Free API Key", desc: "Get a free Google Gemini or Groq key in Settings.")
                stepRow(number: "2", title: "Automatic Sorting", desc: "Songs are clustered into focused genres (max 5 per language).")
                stepRow(number: "3", title: "Seamless Background Sync", desc: "Updates automatically upon download or once daily.")
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isLight ? Color.white : Color.platformSecondarySystemBackground)
            )
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button {
                    MobileHaptics.trigger(.medium)
                    engine.showingSettingsSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                        Text("Configure in Settings")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FluidTheme.musicRed)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)

                Button {
                    MobileHaptics.trigger(.light)
                    Task {
                        await engine.curateEntireLibrary(force: true)
                    }
                } label: {
                    Text("Organize Using Local Heuristics")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(FluidTheme.musicRed)
                }
            }

            Spacer()
        }
    }

    private func stepRow(number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(FluidTheme.musicRed)
                .frame(width: 22, height: 22)
                .background(FluidTheme.musicRed.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isLight ? .primary : .white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func categoryColor(for language: String) -> Color {
        switch language.lowercased() {
        case "hindi": return Color.orange
        case "english": return Color.blue
        case "punjabi": return Color.yellow
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
                Section("AI Provider") {
                    Picker("Provider", selection: $config.selectedProvider) {
                        ForEach(AIProvider.allCases) { prov in
                            Text(prov.displayName).tag(prov)
                        }
                    }
                    .pickerStyle(.menu)

                    if config.selectedProvider != .ollama {
                        SecureField("API Key", text: $config.apiKey)
                            .font(.system(size: 14, design: .monospaced))

                        Link("Get a Free \(config.selectedProvider.displayName) Key ↗", destination: URL(string: config.selectedProvider.instructionsURL)!)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(FluidTheme.musicRed)
                    } else {
                        TextField("Endpoint URL", text: $config.customEndpoint, prompt: Text("http://localhost:11434/v1/chat/completions"))
                            .font(.system(size: 13, design: .monospaced))
                    }
                }

                // Automation Toggles
                Section("Automation Workflows") {
                    Toggle("Curate on Download", isOn: $config.isAutoCurateOnDownloadEnabled)
                        .tint(FluidTheme.musicRed)
                    Text("Automatically analyzes and adds new songs to genre folders when downloaded.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Toggle("Daily Auto-Refresh", isOn: $config.isDailyRefreshEnabled)
                        .tint(FluidTheme.musicRed)
                    Text("Silently updates and verifies your library once every 24 hours.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Re-Analyze Action
                Section {
                    Button {
                        MobileHaptics.trigger(.medium)
                        engine.testingConnection = true
                        engine.connectionMessage = nil
                        Task {
                            await engine.curateEntireLibrary(force: true)
                            engine.testingConnection = false
                            if let err = engine.lastSyncError {
                                engine.connectionMessage = "Failed: \(err)"
                            } else {
                                engine.connectionMessage = "Success! \(engine.curatedLibrary.categories.count) languages organized."
                            }
                        }
                    } label: {
                        HStack {
                            if engine.testingConnection {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text("Re-Analyze Entire Offline Library")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(FluidTheme.musicRed)
                    }
                    .disabled(engine.testingConnection)

                    if let msg = engine.connectionMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(msg.hasPrefix("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("AI Curator Settings")
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
