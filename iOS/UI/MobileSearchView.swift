import SwiftUI

public final class MobileSearchModel: ObservableObject {
    public static let shared = MobileSearchModel()
    
    @Published public var searchQuery: String = ""
    @Published public var selectedMood: String = "All"
    @Published public var searchResults: [Track] = []
    @Published public var recommendedTracks: [Track] = []
    @Published public var isSearching: Bool = false
    @Published public var isLoadingRecommendations: Bool = false
    @Published public var recommendationHeadline: String = "RECOMMENDED FOR YOU"
    @Published public var lastSeedTrackId: String? = nil
    
    public var searchTask: Task<Void, Never>?
    public var recommendTask: Task<Void, Never>?
    
    public init() {}
    
    @MainActor
    public func loadPersonalizedRecommendations(
        history: [Track],
        liked: [Track],
        cached: [Track] = [],
        force: Bool = false
    ) {
        let currentSeed = history.first ?? liked.first ?? cached.first
        let currentSeedId = currentSeed?.id
        
        // If not forced and recommendations are already loaded for this exact seed, skip
        if !force && !recommendedTracks.isEmpty && lastSeedTrackId == currentSeedId {
            return
        }
        
        guard !isLoadingRecommendations else { return }
        isLoadingRecommendations = true
        self.lastSeedTrackId = currentSeedId
        
        if let seed = currentSeed {
            let cleanTitle = seed.title.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? seed.title
            self.recommendationHeadline = "SIMILAR TO \"\(cleanTitle.prefix(22))\""
        } else if cached.first != nil {
            self.recommendationHeadline = "BASED ON YOUR DOWNLOADS"
        } else {
            self.recommendationHeadline = "RECOMMENDED FOR YOU"
        }
        
        recommendTask?.cancel()
        recommendTask = Task {
            var fetched: [Track] = []
            
            if let seed = currentSeed {
                // 1. Primary: YouTube Music algorithmic radio for the seed track
                if let radio = try? await InnerTubeClient.shared.fetchRadioTracks(for: seed.id), !radio.isEmpty {
                    fetched = radio.filter { $0.id != seed.id }
                }
                
                // 2. Secondary enrichment: If radio returned fewer than 6 tracks, search YouTube Music for related tracks by this artist
                if fetched.count < 6 {
                    let artistQuery = seed.artist.trimmingCharacters(in: .whitespaces)
                    if !artistQuery.isEmpty && artistQuery.lowercased() != "youtube music" && artistQuery.lowercased() != "unknown artist" {
                        if let artistResults = try? await InnerTubeClient.shared.search(query: "\(artistQuery) songs") {
                            fetched.append(contentsOf: artistResults.filter { $0.id != seed.id })
                        }
                    }
                }
            } else if let cachedSeed = cached.first {
                let artist = cachedSeed.artist
                if let related = try? await InnerTubeClient.shared.search(query: "\(artist) songs") {
                    fetched = related.filter { $0.id != cachedSeed.id }
                }
            }
            
            // 3. Fallback to real YouTube Music trending/popular query if no history or cache exists yet
            if fetched.isEmpty {
                if let trending = try? await InnerTubeClient.shared.search(query: "Top Global Songs") {
                    fetched = trending
                }
            }
            
            // Strict deduplication to protect against duplicate identifier crashes
            var seen = Set<String>()
            var uniqueTracks: [Track] = []
            for t in fetched {
                if seen.insert(t.id).inserted {
                    uniqueTracks.append(t)
                }
            }
            
            let finalTracks = uniqueTracks
            await MainActor.run {
                self.recommendedTracks = finalTracks
                self.isLoadingRecommendations = false
            }
        }
    }
    
    @MainActor
    public func refreshRecommendationsAsync(
        history: [Track],
        liked: [Track],
        cached: [Track] = []
    ) async {
        loadPersonalizedRecommendations(history: history, liked: liked, cached: cached, force: true)
        while isLoadingRecommendations {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

/// iOS-optimized Search & Discover View for iPhone
/// Follows YouTube Music recommendations: Listen Again (history), Quick Picks (radio based on user taste),
/// and dynamic genre queries with zero mock data.
public struct MobileSearchView: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var model = MobileSearchModel.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    
    // Quick genre / mood pills
    private let quickCategories = ["All", "Chillhop", "Pop Hits", "Lo-Fi Beats", "Indie Rock", "Synthwave", "Jazz Cafe", "Workout", "Focus"]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar Header (Aligned comfortably below Dynamic Island / status bar)
            searchHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            // Mood & Activity Pills (Always visible directly beneath search bar)
            categoriesSection
                .padding(.bottom, 10)
            
            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isSearching {
                        // Loading state
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)
                                .padding(.top, 40)
                            Spacer()
                        }
                    } else if !model.searchQuery.isEmpty {
                        // Search Results List
                        searchResultsSection
                    } else if model.selectedMood != "All" {
                        // Genre Specific Dynamic Results
                        genreResultsSection
                    } else {
                        // YouTube Music Personalized Discover Feed
                        personalizedDiscoverFeed
                    }
                }
                .padding(.bottom, 180) // Generous space so last track scrolls fully clear of MiniPlayer & TabBar
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                MobileHaptics.trigger(.medium)
                if model.selectedMood == "All" && model.searchQuery.isEmpty {
                    await model.refreshRecommendationsAsync(
                        history: player.playHistory,
                        liked: player.likedTracks,
                        cached: MediaCacheManager.shared.getAllCachedTracks()
                    )
                }
            }
        }
        .onAppear {
            let currentSeedId = (player.playHistory.first ?? player.likedTracks.first ?? MediaCacheManager.shared.getAllCachedTracks().first)?.id
            if model.recommendedTracks.isEmpty || (currentSeedId != nil && currentSeedId != model.lastSeedTrackId) {
                model.loadPersonalizedRecommendations(
                    history: player.playHistory,
                    liked: player.likedTracks,
                    cached: MediaCacheManager.shared.getAllCachedTracks()
                )
            }
        }
        .onChange(of: player.playHistory.first?.id) { _, newSeedId in
            if model.selectedMood == "All" && model.searchQuery.isEmpty && newSeedId != model.lastSeedTrackId {
                model.loadPersonalizedRecommendations(
                    history: player.playHistory,
                    liked: player.likedTracks,
                    cached: MediaCacheManager.shared.getAllCachedTracks(),
                    force: true
                )
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Search")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Spacer()
                
                // Theme Appearance Switcher (System, Light, Dark)
                Menu {
                    ForEach(AppThemeMode.allCases) { mode in
                        Button {
                            themeManager.setTheme(mode)
                        } label: {
                            Label(mode.displayName, systemImage: mode.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: themeManager.currentTheme.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(themeManager.currentTheme.displayName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Artists, songs, or lyrics", text: $model.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 15))
                    .onSubmit {
                        dismissKeyboard()
                    }
                    .onChange(of: model.searchQuery) { _, query in
                        if query.isEmpty {
                            selectMood("All")
                        } else {
                            performSearch(query: query)
                        }
                    }
                
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                        dismissKeyboard()
                        selectMood("All")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    private var categoriesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickCategories, id: \.self) { cat in
                    let isSelected = model.selectedMood == cat
                    Button {
                        MobileHaptics.trigger(.selection)
                        withAnimation(FluidTheme.fluidSpring) {
                            selectMood(cat)
                        }
                    } label: {
                        Text(cat)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Discover Sections (YouTube Music Pattern)
    
    private var personalizedDiscoverFeed: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. Listen Again / Recently Played
            if !player.playHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LISTEN AGAIN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(player.playHistory.prefix(8).enumerated()), id: \.offset) { _, track in
                                listenAgainCard(for: track)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            
            // 2. Quick Picks (Personalized algorithmic recommendations)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.recommendationHeadline.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if model.isLoadingRecommendations {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            MobileHaptics.trigger(.light)
                            model.loadPersonalizedRecommendations(
                                history: player.playHistory,
                                liked: player.likedTracks,
                                cached: MediaCacheManager.shared.getAllCachedTracks(),
                                force: true
                            )
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                let recs = model.recommendedTracks
                if recs.isEmpty && !model.isLoadingRecommendations {
                    Text("Play any song to get instant YouTube Music quick picks tailored to your taste.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(recs.prefix(12).enumerated()), id: \.offset) { _, track in
                            mobileTrackRow(for: track)
                        }
                    }
                }
            }
            
            // 3. Favorites Quick Play
            if !player.likedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FROM YOUR FAVORITES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)
                    
                    LazyVStack(spacing: 4) {
                        ForEach(Array(player.likedTracks.prefix(5).enumerated()), id: \.offset) { _, track in
                            mobileTrackRow(for: track)
                        }
                    }
                }
            }
        }
    }
    
    private func listenAgainCard(for track: Track) -> some View {
        Button {
            MobileHaptics.trigger(.medium)
            MobileNavigationCoordinator.shared.revealMiniPlayer()
            player.playWithRadioAutoplay(track: track)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TrackArtworkView(
                    url: track.artworkURL,
                    contentMode: .fill,
                    cornerRadius: 12,
                    placeholderIconSize: 24
                )
                .frame(width: 110, height: 110)
                .clipped()
                
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No tracks found for \"\(model.searchQuery)\"")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                Text("TOP RESULTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                    .padding(.horizontal, 16)
                
                LazyVStack(spacing: 4) {
                    ForEach(Array(model.searchResults.enumerated()), id: \.offset) { _, track in
                        mobileTrackRow(for: track)
                    }
                }
            }
        }
    }
    
    private var genreResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(model.selectedMood.uppercased()) TRACKS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 16)
            
            LazyVStack(spacing: 4) {
                ForEach(Array(model.searchResults.enumerated()), id: \.offset) { _, track in
                    mobileTrackRow(for: track)
                }
            }
        }
    }
    
    private func selectMood(_ mood: String) {
        model.selectedMood = mood
        if mood == "All" {
            model.searchTask?.cancel()
            model.isSearching = false
            model.searchResults = []
            let currentSeedId = (player.playHistory.first ?? player.likedTracks.first ?? MediaCacheManager.shared.getAllCachedTracks().first)?.id
            if model.recommendedTracks.isEmpty || (currentSeedId != nil && currentSeedId != model.lastSeedTrackId) {
                model.loadPersonalizedRecommendations(
                    history: player.playHistory,
                    liked: player.likedTracks,
                    cached: MediaCacheManager.shared.getAllCachedTracks()
                )
            }
        } else {
            // Dynamically query YouTube Music for real playable tracks in this genre
            performSearch(query: "\(mood) music")
        }
    }
    
    private func mobileTrackRow(for track: Track) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        
        return HStack(spacing: 12) {
            // Main clickable playback area
            Button {
                dismissKeyboard()
                MobileHaptics.trigger(.medium)
                MobileNavigationCoordinator.shared.revealMiniPlayer()
                if !model.searchResults.isEmpty && model.searchResults.contains(where: { $0.id == track.id }) {
                    player.playFromSearch(results: model.searchResults, selectedTrack: track)
                } else if !model.recommendedTracks.isEmpty && model.recommendedTracks.contains(where: { $0.id == track.id }) {
                    player.playFromSearch(results: model.recommendedTracks, selectedTrack: track)
                } else {
                    player.playWithRadioAutoplay(track: track)
                }
            } label: {
                HStack(spacing: 12) {
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 10,
                        placeholderIconSize: 14
                    )
                    .frame(width: 48, height: 48)
                    .clipped()
                    .overlay(
                        Group {
                            if isCurrent {
                                Color.black.opacity(0.4)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isCurrent ? FluidTheme.musicRed : .primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            if track.isCached {
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
                    if !model.searchResults.isEmpty && model.searchResults.contains(where: { $0.id == track.id }) {
                        player.playFromSearch(results: model.searchResults, selectedTrack: track)
                    } else if !model.recommendedTracks.isEmpty && model.recommendedTracks.contains(where: { $0.id == track.id }) {
                        player.playFromSearch(results: model.recommendedTracks, selectedTrack: track)
                    } else {
                        player.playWithRadioAutoplay(track: track)
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
                
                // Per-song download / removal option
                if track.isCached || MediaCacheManager.shared.isCached(videoId: track.id) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(isCurrent ? FluidTheme.musicRed.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - Actions
    
    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            model.searchResults = []
            model.isSearching = false
            return
        }
        
        model.searchTask?.cancel()
        model.isSearching = true
        
        model.searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
            guard !Task.isCancelled else { return }
            
            let results = (try? await InnerTubeClient.shared.search(query: trimmed)) ?? []
            
            // Deduplicate search results by ID to guarantee uniqueness in SwiftUI
            var seen = Set<String>()
            var uniqueResults: [Track] = []
            for t in results {
                if seen.insert(t.id).inserted {
                    uniqueResults.append(t)
                }
            }
            
            await MainActor.run {
                if !Task.isCancelled {
                    model.searchResults = uniqueResults
                    model.isSearching = false
                }
            }
        }
    }
    
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
