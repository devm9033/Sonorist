import SwiftUI

@MainActor
public final class AnalyticsViewModel: ObservableObject {
    public static let shared = AnalyticsViewModel()
    @Published public var showResetAlert: Bool = false
    public init() {}
}

public struct AnalyticsView: View {
    @ObservedObject var analytics = ListeningAnalyticsManager.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var viewModel = AnalyticsViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool { colorScheme == .light }
    
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                headerSection
                
                // 3 Hero Visual Highlight Cards
                keyMetricsGrid
                
                // Visual Habit: When You Listen
                timeOfDaySection
                
                // Top Artists Visual Breakdown
                topArtistsSection
                
                // Most Replayed Songs
                topSongsSection
                
                // Footer & Reset
                footerSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .alert("Reset All Analytics?", isPresented: $viewModel.showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Analytics", role: .destructive) {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.fluidSpring) {
                    analytics.resetAll()
                }
            }
        } message: {
            Text("This will permanently clear all listening statistics, including time listened, favorite artists, top tracks, and habit charts. This action cannot be undone.")
        }
    }
    
    // MARK: - Header Section
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(FluidTheme.musicRed)
                        .font(.system(size: 13, weight: .bold))
                    Text("LISTENING INSIGHTS")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(FluidTheme.musicRed)
                }
                
                Text("Your Sound Profile")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text("Visual highlights of what you love and your daily listening rhythm.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !analytics.topTracks.isEmpty {
                Button(action: {
                    FluidHaptics.toggle()
                    let tracksToPlay = analytics.topTracks.map { $0.track }
                    if let first = tracksToPlay.first {
                        player.queue = tracksToPlay
                        player.play(track: first)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Play Top Songs")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(FluidTheme.musicRed)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: FluidTheme.musicRed.opacity(0.3), radius: 6, x: 0, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Key Metrics Grid (3 Essential Hero Cards)
    
    @ViewBuilder
    private var keyMetricsGrid: some View {
        HStack(spacing: 12) {
            heroStatCard(
                title: "Time Listened",
                value: analytics.formattedTotalTime,
                subtitle: "\(analytics.currentStreakDays)-Day Streak 🔥",
                icon: "clock.fill",
                iconColor: FluidTheme.musicRed
            )
            
            heroStatCard(
                title: "Songs Streamed",
                value: "\(analytics.totalSongsPlayed)",
                subtitle: "Total track plays",
                icon: "music.note.list",
                iconColor: .purple
            )
            
            heroStatCard(
                title: "Listening Persona",
                value: analytics.primaryTimeOfDay,
                subtitle: analytics.peakListeningWindow,
                icon: "sparkles",
                iconColor: .orange
            )
        }
    }
    
    @ViewBuilder
    private func heroStatCard(title: String, value: String, subtitle: String, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(iconColor)
                }
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    // MARK: - When You Listen (Visual Gradient Rhythm Bars)
    
    @ViewBuilder
    private var timeOfDaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When You Listen")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            
            let total = max(1, analytics.timeSlotDistribution.values.reduce(0, +))
            
            VStack(spacing: 8) {
                ForEach(TimeOfDaySlot.allCases) { slot in
                    let count = analytics.timeSlotDistribution[slot, default: 0]
                    let ratio = Double(count) / Double(total)
                    let slotColor: Color = {
                        switch slot {
                        case .morning: return .yellow
                        case .afternoon: return .orange
                        case .evening: return FluidTheme.musicRed
                        case .night: return .indigo
                        }
                    }()
                    
                    HStack(spacing: 10) {
                        Image(systemName: slot.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(slotColor)
                            .frame(width: 20)
                        
                        Text(slot.rawValue)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 170, alignment: .leading)
                        
                        // Visual Progress Gradient Bar
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 7)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [slotColor.opacity(0.8), slotColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, barGeo.size.width * CGFloat(ratio)), height: 7)
                            }
                        }
                        .frame(height: 7)
                        
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(14)
            .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Top Artists Section
    
    @ViewBuilder
    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Artists")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            
            if analytics.topArtists.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Start listening to see your top artists here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    Spacer()
                }
                .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(analytics.topArtists.prefix(5).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 10) {
                            Text("#\(idx + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(idx == 0 ? FluidTheme.musicRed : .secondary)
                                .frame(width: 24, alignment: .leading)
                            
                            ZStack {
                                Circle()
                                    .fill(idx == 0 ? FluidTheme.musicRed.opacity(0.15) : Color.primary.opacity(0.06))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundColor(idx == 0 ? FluidTheme.musicRed : .secondary)
                                    .font(.system(size: 15))
                            }
                            
                            Text(item.artist)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(width: 150, alignment: .leading)
                                .lineLimit(1)
                            
                            // Visual percentage bar
                            GeometryReader { barGeo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 6)
                                    Capsule()
                                        .fill(FluidTheme.musicRed)
                                        .frame(width: max(4, barGeo.size.width * CGFloat(item.percentage)), height: 6)
                                }
                            }
                            .frame(height: 6)
                            
                            Text("\(item.count) plays")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 55, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                        
                        if idx < min(4, analytics.topArtists.count - 1) {
                            Divider().opacity(0.15)
                        }
                    }
                }
                .padding(14)
                .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Top Songs Section
    
    @ViewBuilder
    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most Replayed Songs")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            
            if analytics.topTracks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Your most replayed songs will appear here automatically.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    Spacer()
                }
                .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(analytics.topTracks.prefix(5).enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(idx == 0 ? FluidTheme.musicRed : .secondary)
                                .frame(width: 18)
                            
                            // Artwork
                            AsyncImage(url: item.track.artworkURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.gray.opacity(0.3)
                                        .overlay(Image(systemName: "music.note").font(.system(size: 11)))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.track.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                
                                Text(item.track.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Play count flame badge
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(FluidTheme.musicRed)
                                Text("\(item.playCount) plays")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                            
                            // Quick Play Button
                            Button(action: {
                                FluidHaptics.toggle()
                                player.play(track: item.track)
                            }) {
                                Image(systemName: player.currentTrack?.id == item.track.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(FluidTheme.musicRed)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Play Song")
                        }
                        .padding(.vertical, 3)
                        
                        if idx < min(4, analytics.topTracks.count - 1) {
                            Divider().opacity(0.15)
                        }
                    }
                }
                .padding(14)
                .background(isLight ? Color.white.opacity(0.7) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Footer Section
    
    @ViewBuilder
    private var footerSection: some View {
        HStack {
            Text("Insights generated purely from your local playback activity.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                FluidHaptics.tap()
                viewModel.showResetAlert = true
            }) {
                Text("Reset All Analytics")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(FluidTheme.musicRed.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 4)
    }
}
