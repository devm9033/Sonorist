import SwiftUI
import AppKit

@main
struct SonoristApp: App {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    
    var body: some Scene {
        // Main Application Window
        WindowGroup {
            MainContentView()
                .environmentObject(player)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .background(FluidTheme.glassMaterial)
        }
        .windowStyle(TitleBarWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .defaultSize(width: 800, height: 600)
        .commands {
            // Playback Menu
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("Next Track") {
                    player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                
                Button("Previous Track") {
                    player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                
                Divider()
                
                Button(player.isShuffle ? "Disable Shuffle" : "Enable Shuffle") {
                    player.toggleShuffle()
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Button(player.repeatMode.title) {
                    player.toggleRepeatMode()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            
            // View & Window Menu
            CommandMenu("View") {
                Button(AppNavigationState.shared.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation(FluidTheme.fluidSpring) {
                        AppNavigationState.shared.isSidebarVisible.toggle()
                    }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                
                Divider()
                
                Button(player.isImmersiveViewActive ? "Exit Immersive View" : "Full-Window Immersive View") {
                    withAnimation(FluidTheme.fluidSpring) {
                        player.isImmersiveViewActive.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command])
                
                Divider()
                
                Menu("Appearance Theme") {
                    Button(action: { themeManager.setTheme(.light) }) {
                        HStack {
                            Text("Light (White)")
                            if themeManager.currentTheme == .light {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { themeManager.setTheme(.dark) }) {
                        HStack {
                            Text("Dark")
                            if themeManager.currentTheme == .dark {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { themeManager.setTheme(.system) }) {
                        HStack {
                            Text("Match System")
                            if themeManager.currentTheme == .system {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            // Audio Controls Menu
            CommandMenu("Audio") {
                Button(player.isAutoplayEnabled ? "Disable Autoplay Radio" : "Enable Autoplay Radio") {
                    player.isAutoplayEnabled.toggle()
                }
                
                Divider()
                
                Button("Graphic Equalizer...") {
                    player.showEqualizerSheet = true
                }
                .keyboardShortcut("e", modifiers: [.option, .command])
                
                Button("Up Next Queue...") {
                    player.showQueueSheet = true
                }
                .keyboardShortcut("u", modifiers: [.command])
                
                Button("Live Lyrics...") {
                    player.showLyricsSheet = true
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
        
        // Native macOS Settings Window (⌘,)
        Settings {
            SettingsView()
                .environmentObject(player)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
        
        // Menu Bar Companion Popover
        MenuBarExtra("Sonorist", systemImage: player.isPlaying ? "music.note" : "music.note.list") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
