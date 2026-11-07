import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine

/// Supported application theme modes conforming to Apple Human Interface Guidelines
public enum AppThemeMode: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    public var description: String {
        switch self {
        case .system: return "Automatically matches your macOS system appearance preference"
        case .light: return "Bright, airy white appearance across all windows and Now Playing"
        case .dark: return "Deep contrast dark appearance for reduced eye strain"
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Central state manager for system-wide application theme and appearance
@MainActor
public final class AppThemeManager: ObservableObject {
    public static let shared = AppThemeManager()
    
    public static let themeDefaultsKey = "Sonorist.AppThemeMode"
    
    @Published public var currentTheme: AppThemeMode {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: AppThemeManager.themeDefaultsKey)
            applyAppearance()
        }
    }
    
    public init() {
        if let saved = UserDefaults.standard.string(forKey: AppThemeManager.themeDefaultsKey),
           let mode = AppThemeMode(rawValue: saved) {
            self.currentTheme = mode
        } else {
            self.currentTheme = .system
        }
        applyAppearance()
        
        // Listen for live theme modifications from iOS native Settings app (Settings.bundle)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let saved = UserDefaults.standard.string(forKey: AppThemeManager.themeDefaultsKey),
                   let mode = AppThemeMode(rawValue: saved),
                   mode != self.currentTheme {
                    withAnimation(FluidTheme.fluidSpring) {
                        self.currentTheme = mode
                    }
                }
            }
        }
    }
    
    /// Switch theme mode with animated transition and physical haptic feedback
    public func setTheme(_ mode: AppThemeMode) {
        guard mode != currentTheme else { return }
        FluidHaptics.tap()
        withAnimation(FluidTheme.fluidSpring) {
            self.currentTheme = mode
        }
    }
    
    /// Synchronize NSApplication / UIApplication window chrome, titlebars, menus and sheets
    public func applyAppearance() {
        #if os(macOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.currentTheme {
            case .system:
                NSApp?.appearance = nil
            case .light:
                NSApp?.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp?.appearance = NSAppearance(named: .darkAqua)
            }
        }
        #elseif os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let style: UIUserInterfaceStyle
            switch self.currentTheme {
            case .system:
                style = .unspecified
            case .light:
                style = .light
            case .dark:
                style = .dark
            }
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }
        #endif
    }
}
