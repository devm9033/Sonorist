import SwiftUI
import Combine

@MainActor
public final class SearchViewModel: ObservableObject {
    public static let shared = SearchViewModel()
    
    @Published public var searchText: String = ""
    @Published public var isSearching: Bool = false
    @Published public var searchResults: [Track] = []
    @Published public var suggestions: [String] = []
    @Published public var libraryMatches: [Track] = []
    @Published public var errorMessage: String?
    
    private var searchTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        // Debounce typing to fetch suggestions and live results
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                self?.handleSearchTextChange(text)
            }
            .store(in: &cancellables)
    }
    
    public func handleSearchTextChange(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.suggestions = []
            self.searchResults = []
            self.libraryMatches = []
            return
        }
        
        // 1. Instant local library matching (0ms latency)
        let q = trimmed.lowercased()
        let allLocal = AudioPlayerEngine.shared.likedTracks + MediaCacheManager.shared.getAllCachedTracks()
        self.libraryMatches = allLocal.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            ($0.album?.lowercased().contains(q) ?? false)
        }
        
        // 2. Fetch live suggestions
        suggestionsTask?.cancel()
        suggestionsTask = Task {
            let fetched = await InnerTubeClient.shared.fetchSearchSuggestions(query: trimmed)
            if !Task.isCancelled {
                self.suggestions = fetched
            }
        }
        
        // 3. Live debounced search if query is 3+ characters
        if trimmed.count >= 3 {
            performSearch(query: trimmed)
        }
    }
    
    public func performSearch(query: String? = nil) {
        let textToSearch = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSearch.isEmpty else { return }
        
        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        
        searchTask = Task {
            do {
                let results = try await InnerTubeClient.shared.search(query: textToSearch)
                if !Task.isCancelled {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
    
    public func selectSuggestion(_ suggestion: String) {
        FluidHaptics.tap()
        self.searchText = suggestion
        self.suggestions = []
        performSearch(query: suggestion)
    }
}

public struct SearchView: View {
    @ObservedObject var viewModel = SearchViewModel.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                    
                    TextField("Search songs, artists, or albums on YouTube Music...", text: $viewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(FluidTheme.bodyFont)
                        .onSubmit {
                            FluidHaptics.tap()
                            viewModel.performSearch()
                        }
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            FluidHaptics.tap()
                            viewModel.searchText = ""
                            viewModel.searchResults = []
                            viewModel.suggestions = []
                            viewModel.libraryMatches = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if viewModel.isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                // Search Suggestions Pills (Instant Help)
                if !viewModel.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.suggestions, id: \.self) { item in
                                Button(action: {
                                    viewModel.selectSuggestion(item)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(item)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.05))
                                    .foregroundColor(.primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 10)
            
            // Content Stage
            if viewModel.searchResults.isEmpty && viewModel.libraryMatches.isEmpty && !viewModel.isSearching {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Search YouTube Music & Library")
                        .font(FluidTheme.titleFont)
                        .foregroundColor(.secondary)
                    Text("Start typing to see live suggestions, instant library matches, and songs.")
                        .font(FluidTheme.captionFont)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. Instant Local / Cached Matches
                        if !viewModel.libraryMatches.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "internaldrive.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                    Text("From Your Library")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                LazyVStack(spacing: 4) {
                                    ForEach(viewModel.libraryMatches) { track in
                                        TrackRowView(
                                            track: track,
                                            isCurrent: player.currentTrack?.id == track.id,
                                            isPlaying: player.isPlaying,
                                            onPlay: {
                                                player.queue = viewModel.libraryMatches
                                                player.play(track: track)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        
                        // 2. YouTube Music Online Results
                        if !viewModel.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(FluidTheme.musicRed)
                                        .font(.system(size: 12))
                                    Text("YouTube Music Results")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                LazyVStack(spacing: 4) {
                                    ForEach(viewModel.searchResults) { track in
                                        TrackRowView(
                                            track: track,
                                            isCurrent: player.currentTrack?.id == track.id,
                                            isPlaying: player.isPlaying,
                                            onPlay: {
                                                player.playWithRadioAutoplay(track: track)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}
