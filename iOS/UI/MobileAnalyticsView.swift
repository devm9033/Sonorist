import SwiftUI

public final class MobileAnalyticsModel: ObservableObject {
    public static let shared = MobileAnalyticsModel()
    @Published public var showSettings: Bool = false
    @Published public var selectedLanguage: String? = nil
    @Published public var selectedGenre: String? = nil
    @Published public var selectedTimeSlot: TimeOfDaySlot? = nil
    @Published public var selectedRhythmSlice: String? = nil
    @Published public var selectedMetricChip: String? = nil
    @Published public var isRefreshing: Bool = false
    public init() {}
}

/// iOS-optimized Listening Insights & Music Profile View for iPhone
public struct MobileAnalyticsView: View {
    @ObservedObject private var analytics = ListeningAnalyticsManager.shared
    @ObservedObject private var insights = AIInsightsEngine.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    @ObservedObject private var model = MobileAnalyticsModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    private var isLight: Bool { colorScheme == .light }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header (Pinned comfortably below Dynamic Island / status bar)
            headerSection
            
            // Scrollable Content with Native Pull-To-Refresh
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if analytics.totalSongsPlayed == 0 {
                        zeroStateView
                    } else if !insights.isThresholdReached {
                        // Calibration state (1 to 9 songs)
                        calibrationCard
                        
                        // Show current rotation so user still sees their real data immediately
                        if let topTrack = analytics.topTracks.first {
                            heroMostPlayedCard(topTrack: topTrack)
                        }
                        
                        if analytics.topTracks.count > 1 {
                            topSongsCard
                        }
                        
                        soundAndGenreCard
                        habitsAndRhythmsCard
                    } else {
                        // Full Music Profile (>= 10 songs)
                        
                        // 1. #1 Most Played Track (Hero Card)
                        if let topTrack = analytics.topTracks.first {
                            heroMostPlayedCard(topTrack: topTrack)
                        }
                        
                        // 2. Top 3 Songs in Heavy Rotation
                        if analytics.topTracks.count > 1 {
                            topSongsCard
                        }
                        
                        // 3. Sound & Cultural DNA (Languages & Genres Side-by-Side Donuts)
                        soundAndGenreCard
                        
                        // 4. Habits & Rhythms (Day & Night + Play vs Skip with Total Listening Time)
                        habitsAndRhythmsCard
                        
                        // 5. Top Artists Roster
                        if !analytics.topArtists.isEmpty {
                            topArtistsCard
                        }
                        
                        // 6. Objective Musicologist Commentary (AI or Local Grounded)
                        musicologistCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 180) // Generous space so content scrolls clear of MiniPlayer & TabBar
            }
            .refreshable {
                MobileHaptics.trigger(.medium)
                model.isRefreshing = true
                await insights.generateInsights(force: true)
                model.isRefreshing = false
            }
        }
        .sheet(isPresented: $model.showSettings) {
            MobileSettingsView(isPresentedAsSheet: true)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task {
            if insights.shouldAutoSync {
                await insights.generateInsights(force: false)
            }
        }
    }
    
    // MARK: - Header (Clean, Pinned, Zero AI Badges)
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Insights")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Your listening habits & sound profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Theme Switcher Menu
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // MARK: - Zero State (Brand New App Install)
    
    private var zeroStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 16)
            
            ZStack {
                Circle()
                    .fill(FluidTheme.musicRed.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            VStack(spacing: 6) {
                Text("No Listening Data Yet")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                
                Text("Sonorist logs your authentic playback locally on your device. Play a few songs to view your real listening time, top tracks, and sound profile.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("100% on-device & private")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            
            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(cardBackground)
    }
    
    // MARK: - Calibration State (1 to 9 Tracks)
    
    private var calibrationCard: some View {
        let count = analytics.totalSongsPlayed
        let progress = insights.thresholdProgress
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("BUILDING SOUND PROFILE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(count) / 10 songs")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            // Visual Progress Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [FluidTheme.musicRed, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, geo.size.width * CGFloat(progress)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
                }
            }
            .frame(height: 8)
            
            Text("Logged \(analytics.formattedTotalTime) of authentic listening. Once you reach 10 songs, deep audio habits and cultural breakdown will fully activate.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 1. Hero Most Played Track ("Heavy Rotation")
    
    private func heroMostPlayedCard(topTrack: TrackAnalytics) -> some View {
        let track = topTrack.track
        let playCount = topTrack.playCount
        let mins = max(1, Int(topTrack.totalSeconds / 60))
        let isSelected = model.selectedMetricChip != nil
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("MOST PLAYED TRACK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Mini Visualizer Indicator
                HStack(spacing: 2) {
                    ForEach(0..<4) { idx in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: CGFloat([8, 14, 11, 6][idx]))
                    }
                }
            }
            
            HStack(spacing: 14) {
                // Large Artwork Tile with Glow
                ZStack {
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 14,
                        placeholderIconSize: 24
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: FluidTheme.musicRed.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Style & Quality Tag
                    HStack(spacing: 6) {
                        Text("Lossless M4A")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(FluidTheme.downloadGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FluidTheme.downloadGreen.opacity(0.12))
                            .clipShape(Capsule())
                        
                        let detected = AIPlaylistEngine.shared.classifyTrackHeuristically(track).language
                        Text(detected)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            
            // Interactive Metric Chips (Tap to inspect)
            HStack(spacing: 8) {
                metricChip(
                    id: "plays",
                    icon: "repeat",
                    title: "\(playCount) \(playCount == 1 ? "play" : "plays")",
                    detail: "Repeated in rotation"
                )
                
                metricChip(
                    id: "time",
                    icon: "clock.fill",
                    title: "\(mins) mins",
                    detail: "Total listening time"
                )
                
                metricChip(
                    id: "completion",
                    icon: "checkmark.circle.fill",
                    title: "\(Int(analytics.completionPercentage * 100))%",
                    detail: "Finished in full"
                )
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func metricChip(id: String, icon: String, title: String, detail: String) -> some View {
        let isSelected = model.selectedMetricChip == id
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if model.selectedMetricChip == id {
                    model.selectedMetricChip = nil
                } else {
                    model.selectedMetricChip = id
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white : FluidTheme.musicRed)
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                Text(isSelected ? detail : "Tap for details")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? Color.white.opacity(0.85) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 2. Top Songs in Rotation
    
    private var topSongsCard: some View {
        let topThree = Array(analytics.topTracks.prefix(3))
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("TOP SONGS IN ROTATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Heavy Rotation")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(topThree.enumerated()), id: \.element.track.id) { index, item in
                    let track = item.track
                    let rankColor: Color = index == 0 ? FluidTheme.musicRed : (index == 1 ? .orange : .purple)
                    
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(rankColor)
                            .frame(width: 24)
                        
                        TrackArtworkView(
                            url: track.artworkURL,
                            contentMode: .fill,
                            cornerRadius: 8,
                            placeholderIconSize: 16
                        )
                        .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(track.artist)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.playCount) \(item.playCount == 1 ? "play" : "plays")")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            let mins = max(1, Int(item.totalSeconds / 60))
                            Text("\(mins) mins")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 3. Sound & Cultural DNA (Languages & Genres Side-by-Side Donuts)
    
    private var soundAndGenreCard: some View {
        let languages = insights.computedLanguageSpectrum
        let genres = insights.computedGenreSpectrum
        let hasData = !languages.isEmpty
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.indigo)
                    Text("SOUND & CULTURAL DNA")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if hasData {
                    Text("Tap to inspect")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Analyzing...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            // Side-by-Side Pie / Donut Charts
            HStack(alignment: .top, spacing: 16) {
                languageDonutView
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 110)
                
                genreDonutView
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            
            // Interactive Detail Bar
            if let lang = model.selectedLanguage, let target = languages.first(where: { $0.language == lang }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForName(target.colorName))
                        .frame(width: 7, height: 7)
                    Text("\(target.language): \(target.count) \(target.count == 1 ? "track" : "tracks") (\(Int(target.percentage * 100))% of rotation)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 2)
            } else if let gen = model.selectedGenre, let target = genres.first(where: { $0.genre == gen }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForName(target.colorName))
                        .frame(width: 7, height: 7)
                    Text("\(target.genre): \(target.count) \(target.count == 1 ? "track" : "tracks") (\(Int(target.percentage * 100))% of styles)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 2)
            } else if !hasData {
                Text("We're still analyzing this data. Keep listening to reveal your language and style breakdown.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private var languageDonutView: some View {
        let languages = insights.computedLanguageSpectrum
        let hasData = !languages.isEmpty
        let topLang = languages.first
        
        let slices: [(start: Double, end: Double, color: Color)] = {
            var acc = 0.0
            var res: [(start: Double, end: Double, color: Color)] = []
            for item in languages {
                let s = acc
                let e = acc + item.percentage
                acc = e
                res.append((s, e, colorForName(item.colorName)))
            }
            return res
        }()
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if let curr = model.selectedLanguage,
                   let currIdx = languages.firstIndex(where: { $0.language == curr }),
                   currIdx + 1 < languages.count {
                    model.selectedLanguage = languages[currIdx + 1].language
                } else {
                    model.selectedLanguage = languages.first?.language
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 82, height: 82)
                    
                    if hasData {
                        ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                            Circle()
                                .trim(from: CGFloat(slice.start), to: CGFloat(slice.end))
                                .stroke(slice.color, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    
                    VStack(spacing: 2) {
                        if hasData, let top = topLang {
                            let active = languages.first(where: { $0.language == model.selectedLanguage }) ?? top
                            let code = String(active.language.prefix(2)).uppercased()
                            Text(code)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(colorForName(active.colorName))
                            Text("\(Int(active.percentage * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        } else {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Analyzing")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                VStack(spacing: 2) {
                    Text("Languages")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if hasData, let top = topLang {
                        let active = languages.first(where: { $0.language == model.selectedLanguage }) ?? top
                        Text(active.language)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Still analyzing")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var genreDonutView: some View {
        let genres = insights.computedGenreSpectrum
        let hasData = !genres.isEmpty
        let topGenre = genres.first
        
        let slices: [(start: Double, end: Double, color: Color)] = {
            var acc = 0.0
            var res: [(start: Double, end: Double, color: Color)] = []
            for item in genres {
                let s = acc
                let e = acc + item.percentage
                acc = e
                res.append((s, e, colorForName(item.colorName)))
            }
            return res
        }()
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if let curr = model.selectedGenre,
                   let currIdx = genres.firstIndex(where: { $0.genre == curr }),
                   currIdx + 1 < genres.count {
                    model.selectedGenre = genres[currIdx + 1].genre
                } else {
                    model.selectedGenre = genres.first?.genre
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 82, height: 82)
                    
                    if hasData {
                        ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                            Circle()
                                .trim(from: CGFloat(slice.start), to: CGFloat(slice.end))
                                .stroke(slice.color, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    
                    VStack(spacing: 2) {
                        if hasData, let top = topGenre {
                            let active = genres.first(where: { $0.genre == model.selectedGenre }) ?? top
                            Image(systemName: active.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colorForName(active.colorName))
                            Text("\(Int(active.percentage * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        } else {
                            Image(systemName: "guitars.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Analyzing")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                VStack(spacing: 2) {
                    Text("Genres & Styles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if hasData, let top = topGenre {
                        let active = genres.first(where: { $0.genre == model.selectedGenre }) ?? top
                        Text(active.genre)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Still analyzing")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 4. Habits & Rhythms (Side-by-Side Donut Charts)
    
    private var habitsAndRhythmsCard: some View {
        let stats = analytics.completionCounts
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                        Text("HABITS & RHYTHMS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text("Day & night listening patterns")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Embedded Total Listening Time
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text(analytics.formattedTotalTime)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
            
            // Side-by-Side Pie / Donut Charts
            HStack(alignment: .top, spacing: 16) {
                circadianDonutView
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 110)
                
                listeningRhythmDonutView
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            
            // Interactive Bottom Insight Bar (if tapped)
            if let slot = model.selectedTimeSlot, analytics.hasCircadianData {
                let count = analytics.timeSlotDistribution[slot, default: 0]
                let pct = Int(analytics.timeSlotPercentage(for: slot) * 100)
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForSlot(slot))
                        .frame(width: 7, height: 7)
                    Text("\(slot.rawValue): \(count) songs played (\(pct)% of listening)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 2)
            } else if let rhythm = model.selectedRhythmSlice, analytics.hasJournalData {
                HStack(spacing: 6) {
                    Circle()
                        .fill(rhythm == "skip" ? Color.secondary : FluidTheme.downloadGreen)
                        .frame(width: 7, height: 7)
                    if rhythm == "skip" {
                        Text("Quick Skips: \(stats.earlySkips) skipped before 15 seconds")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Deep Play: \(stats.fullPlays) songs finished in full")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private var circadianDonutView: some View {
        let total = Double(analytics.timeSlotDistribution.values.reduce(0, +))
        let slots = analytics.timeSlotDistribution
        let hasData = analytics.hasCircadianData
        
        let morningRatio = hasData && total > 0 ? Double(slots[.morning, default: 0]) / total : 0.0
        let afternoonRatio = hasData && total > 0 ? Double(slots[.afternoon, default: 0]) / total : 0.0
        let eveningRatio = hasData && total > 0 ? Double(slots[.evening, default: 0]) / total : 0.0
        let nightRatio = hasData && total > 0 ? Double(slots[.night, default: 0]) / total : 0.0
        
        let mEnd = morningRatio
        let aEnd = mEnd + afternoonRatio
        let eEnd = aEnd + eveningRatio
        let nEnd = 1.0
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if let curr = model.selectedTimeSlot {
                    switch curr {
                    case .morning: model.selectedTimeSlot = .afternoon
                    case .afternoon: model.selectedTimeSlot = .evening
                    case .evening: model.selectedTimeSlot = .night
                    case .night: model.selectedTimeSlot = nil
                    }
                } else {
                    model.selectedTimeSlot = .morning
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Base background ring
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 82, height: 82)
                    
                    if hasData {
                        // Morning slice (Orange)
                        if morningRatio > 0 {
                            Circle()
                                .trim(from: 0, to: CGFloat(mEnd))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        // Afternoon slice (Yellow)
                        if afternoonRatio > 0 {
                            Circle()
                                .trim(from: CGFloat(mEnd), to: CGFloat(aEnd))
                                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        // Evening slice (Purple)
                        if eveningRatio > 0 {
                            Circle()
                                .trim(from: CGFloat(aEnd), to: CGFloat(eEnd))
                                .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        // Night slice (Red)
                        if nightRatio > 0 {
                            Circle()
                                .trim(from: CGFloat(eEnd), to: CGFloat(nEnd))
                                .stroke(FluidTheme.musicRed, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    
                    // Donut Center Content
                    VStack(spacing: 2) {
                        if hasData {
                            if let sel = model.selectedTimeSlot {
                                let pct = Int(analytics.timeSlotPercentage(for: sel) * 100)
                                Image(systemName: iconForSlot(sel))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(colorForSlot(sel))
                                Text("\(pct)%")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.primary)
                            } else {
                                Image(systemName: "sun.and.horizon.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.orange)
                                Text("Peak")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Image(systemName: "clock")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Analyzing")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                VStack(spacing: 2) {
                    Text("Day & Night")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if hasData {
                        Text(model.selectedTimeSlot?.rawValue ?? (analytics.peakListeningWindow.components(separatedBy: " (").first ?? "Active"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Still analyzing")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var listeningRhythmDonutView: some View {
        let hasData = analytics.hasJournalData
        let stats = analytics.completionCounts
        let completionRatio = analytics.completionPercentage
        let completionPct = Int(completionRatio * 100)
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if model.selectedRhythmSlice == nil {
                    model.selectedRhythmSlice = "deep"
                } else if model.selectedRhythmSlice == "deep" {
                    model.selectedRhythmSlice = "skip"
                } else {
                    model.selectedRhythmSlice = nil
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Base background ring
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 82, height: 82)
                    
                    if hasData {
                        // Full Play slice (Emerald Green)
                        if completionRatio > 0 {
                            Circle()
                                .trim(from: 0, to: CGFloat(completionRatio))
                                .stroke(FluidTheme.downloadGreen, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        // Skip slice (Coral / Secondary)
                        if completionRatio < 1.0 {
                            Circle()
                                .trim(from: CGFloat(completionRatio), to: 1.0)
                                .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                                .frame(width: 82, height: 82)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    
                    // Donut Center Content
                    VStack(spacing: 2) {
                        if hasData {
                            if model.selectedRhythmSlice == "skip" {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text("\(max(0, 100 - completionPct))%")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(FluidTheme.downloadGreen)
                                Text("\(completionPct)%")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        } else {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Analyzing")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                VStack(spacing: 2) {
                    Text("Play vs Skip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if hasData {
                        Text("\(stats.fullPlays) full • \(stats.earlySkips) skips")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Still analyzing")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForSlot(_ slot: TimeOfDaySlot) -> String {
        switch slot {
        case .morning: return "sun.and.horizon.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
    
    private func colorForSlot(_ slot: TimeOfDaySlot) -> Color {
        switch slot {
        case .morning: return .orange
        case .afternoon: return .yellow
        case .evening: return .purple
        case .night: return FluidTheme.musicRed
        }
    }
    
    // MARK: - 5. Top Artists Roster
    
    private var topArtistsCard: some View {
        let artists = analytics.topArtists.prefix(3)
        let total = Double(max(1, analytics.totalSongsPlayed))
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.purple)
                    Text("TOP ARTISTS IN ROTATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(analytics.topArtists.count) Total")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, item in
                    let rankColor: Color = index == 0 ? FluidTheme.musicRed : (index == 1 ? .orange : .purple)
                    
                    HStack(spacing: 12) {
                        // Rank Badge
                        Text("#\(index + 1)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(rankColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.artist)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // Visual percentage bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 5)
                                    
                                    Capsule()
                                        .fill(rankColor)
                                        .frame(width: max(6, geo.size.width * CGFloat(item.percentage)), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        
                        Spacer()
                        
                        Text("\(item.count) \(item.count == 1 ? "play" : "plays")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 6. Musicologist Commentary (Objective & Grounded)
    
    private var musicologistCard: some View {
        let story = insights.currentStory
        let hasAPIKey = !AIProviderConfig.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                        Text("MUSICOLOGIST SUMMARY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text("Synthesizes your musical themes, artist coherence & habits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(story?.modelUsed ?? (hasAPIKey ? "AI Musicologist" : "On-Device"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(story?.narrativeStory ?? "Your listening patterns show authentic engagement with acoustic and melodic arrangements, listening through songs with high consistency.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .padding(.vertical, 2)
            
            if !hasAPIKey {
                Divider()
                    .padding(.vertical, 2)
                
                Button {
                    model.showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(FluidTheme.musicRed)
                        Text("Connect API Key in Settings for deep musicological commentary")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(FluidTheme.musicRed)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if let date = insights.lastGeneratedDate {
                HStack {
                    Spacer()
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened)) • Pull down to refresh")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(isLight ? 0.04 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(isLight ? 0.08 : 0.09), lineWidth: 0.5)
            )
    }
    
    private func colorForName(_ name: String) -> Color {
        switch name {
        case "musicRed": return FluidTheme.musicRed
        case "amber": return .orange
        case "indigo": return .indigo
        case "teal": return .teal
        case "purple": return .purple
        case "emerald": return .green
        default: return FluidTheme.musicRed
        }
    }
}
