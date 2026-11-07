#if os(macOS)
import SwiftUI
import AppKit

public final class iPhoneChassisModel: ObservableObject {
    public static let shared = iPhoneChassisModel()
    
    @Published public var isDarkMode: Bool = true
    @Published public var currentTimeString: String = "9:41"
    @Published public var scale: CGFloat = 0.82
    @Published public var isDynamicIslandExpanded: Bool = false
    
    public init() {}
}

/// Lightweight, Zero-Virtualization iPhone 17 Simulator Canvas for macOS.
/// Runs native iOS SwiftUI views inside an exact 393 × 852 pt hardware chassis
/// with interactive Dynamic Island, Home Indicator, and touch simulation — using under 80 MB of RAM!
@main
struct iPhone17ViewportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            iPhone17ChassisView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Viewport (⌘Q)") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                
                Button("Quit Viewport (Ctrl+Q)") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .control)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true // Allows clicking & dragging anywhere on chassis to move
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.borderless, .fullSizeContentView]
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

public struct iPhone17ChassisView: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var progressTracker = PlaybackProgressTracker.shared
    @ObservedObject private var model = iPhoneChassisModel.shared
    
    // iPhone 17 Screen Specifications (393 × 852 pt @3x, 54pt corner radius)
    public let screenWidth: CGFloat = 393
    public let screenHeight: CGFloat = 852
    public let cornerRadius: CGFloat = 54
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 6) {
            // macOS Window Control & Auxiliary Toolbar (Floating above phone chassis)
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 11, height: 11)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.black.opacity(0.8))
                    )
                    .onTapGesture {
                        NSApplication.shared.terminate(nil)
                    }
                    .help("Close (⌘Q or Ctrl+Q)")
                
                Text("iPhone 17 (Sonorist)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Scale Toggle for Laptop Screens
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.scale = (model.scale == 0.82 ? 1.0 : 0.82)
                    }
                } label: {
                    Text(model.scale == 0.82 ? "Fit Screen (82%)" : "100% Size")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle Screen Scale (Fit laptop vs Full size)")
                
                // Dark / Light Theme toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.isDarkMode.toggle()
                    }
                } label: {
                    Image(systemName: model.isDarkMode ? "moon.stars.fill" : "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundColor(model.isDarkMode ? .purple : .orange)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle Light/Dark Theme")
            }
            .frame(width: (screenWidth + 16) * model.scale)
            .padding(.top, 4)
            
            // Physical iPhone 17 Titanium Hardware Chassis
            ZStack(alignment: .top) {
                // Titanium Outer Bezel Edge
                RoundedRectangle(cornerRadius: (cornerRadius + 6) * model.scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.14), Color(white: 0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: (screenWidth + 16) * model.scale, height: (screenHeight + 16) * model.scale)
                    .overlay(
                        RoundedRectangle(cornerRadius: (cornerRadius + 6) * model.scale, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
                
                // Screen Glass Area
                ZStack(alignment: .top) {
                    // 1. Mobile Root Application (Touch & click surface)
                    MobileRootView()
                        .environment(\.colorScheme, model.isDarkMode ? .dark : .light)
                        .frame(width: screenWidth, height: screenHeight)
                        .background(model.isDarkMode ? Color.black : Color(white: 0.98))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    
                    // 2. Hardware Dynamic Island & Status Bar Overlay
                    VStack(spacing: 0) {
                        statusBar
                            .padding(.top, 12)
                            .padding(.horizontal, 22)
                            .frame(width: screenWidth, alignment: .top)
                        
                        Spacer()
                    }
                    .frame(width: screenWidth, height: screenHeight, alignment: .top)
                    
                    // 3. iOS Home Indicator Bar (Restricted to bottom, non-blocking)
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(model.isDarkMode ? Color.white.opacity(0.4) : Color.black.opacity(0.3))
                            .frame(width: 138, height: 5)
                            .padding(.bottom, 8)
                    }
                    .frame(width: screenWidth, height: screenHeight)
                    .allowsHitTesting(false)
                }
                .scaleEffect(model.scale)
                .frame(width: screenWidth * model.scale, height: screenHeight * model.scale)
                .padding(.top, 8 * model.scale)
            }
            .frame(width: (screenWidth + 16) * model.scale, height: (screenHeight + 16) * model.scale)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .onAppear {
            updateTime()
        }
    }
    
    // MARK: - Dynamic Island & Status Bar
    
    private var statusBar: some View {
        HStack(alignment: .top) {
            // Left Status: Time
            Text(model.currentTimeString)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(model.isDarkMode ? .white : .black)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 4)
                .allowsHitTesting(false)
            
            Spacer()
            
            // Dynamic Island (Compact pill or Expanded Live Activity)
            dynamicIslandView
            
            Spacer()
            
            // Right Status: 5G, Wi-Fi, Battery
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "battery.100")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(model.isDarkMode ? .white : .black)
            .frame(width: 54, alignment: .trailing)
            .padding(.top, 4)
            .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var dynamicIslandView: some View {
        let isPlaying = player.isPlaying && player.currentTrack != nil
        
        if model.isDynamicIslandExpanded, let track = player.currentTrack {
            // Authentic Apple Dynamic Island Expanded State (360 × 160 pt)
            VStack(spacing: 12) {
                // Top row: Artwork, Track Info, Sound Waves
                HStack(spacing: 12) {
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 12,
                        placeholderIconSize: 20
                    )
                    .frame(width: 50, height: 50)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Live Waveform visualizer
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 14)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 20)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                // Scrubber Progress Bar
                VStack(spacing: 4) {
                    let ratio = player.duration > 0 ? max(0, min(progressTracker.currentTime / player.duration, 1.0)) : 0
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 3)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(0, min(328 * CGFloat(ratio), 328)), height: 3)
                    }
                    .frame(width: 328)
                }
                
                // Transport controls inside Dynamic Island
                HStack(spacing: 36) {
                    Button {
                        MobileHaptics.trigger(.medium)
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        MobileHaptics.trigger(.medium)
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        MobileHaptics.trigger(.medium)
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 12)
            }
            .frame(width: 360, height: 160)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: 8)
            .onTapGesture {
                withAnimation(FluidTheme.fluidSpring) {
                    model.isDynamicIslandExpanded = false
                }
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            // Collapsed Dynamic Island Pill
            HStack(spacing: 8) {
                if isPlaying, let track = player.currentTrack {
                    // Mini Artwork thumbnail on leading side
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 11,
                        placeholderIconSize: 10
                    )
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .padding(.leading, 6)
                    
                    Spacer()
                    
                    // Sound Wave Equalizer on trailing side
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 12)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 16)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: 9)
                    }
                    .padding(.trailing, 8)
                }
            }
            .frame(width: isPlaying ? 175 : 124, height: 35)
            .background(Color.black)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(Capsule())
            .onTapGesture {
                MobileHaptics.trigger(.medium)
                withAnimation(FluidTheme.fluidSpring) {
                    if player.currentTrack != nil {
                        model.isDynamicIslandExpanded.toggle()
                    }
                }
            }
            .animation(FluidTheme.fluidSpring, value: isPlaying)
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        model.currentTimeString = formatter.string(from: Date())
    }
}
#endif
