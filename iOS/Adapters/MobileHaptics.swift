import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Unified tactile haptic feedback provider for Sonorist on iOS and Mac simulation
public enum MobileHapticType {
    case light
    case medium
    case heavy
    case selection
    case success
    case error
}

public enum MobileHaptics {
    @MainActor
    public static func trigger(_ type: MobileHapticType) {
        #if os(iOS)
        switch type {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        #else
        // When running in Mac Viewport simulation, route through FluidHaptics
        switch type {
        case .light, .selection:
            FluidHaptics.toggle()
        case .medium, .heavy, .success, .error:
            FluidHaptics.snap()
        }
        #endif
    }
}

// MARK: - Global Floating Toast HUD

public final class MobileToastManager: ObservableObject {
    public static let shared = MobileToastManager()
    
    @Published public var message: String? = nil
    @Published public var icon: String? = nil
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    @MainActor
    public func show(message: String, icon: String = "checkmark.circle.fill") {
        MobileHaptics.trigger(.success)
        withAnimation(FluidTheme.fluidSpring) {
            self.message = message
            self.icon = icon
        }
        
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(FluidTheme.fluidSpring) {
                    self.message = nil
                    self.icon = nil
                }
            }
        }
    }
}

public struct ToastOverlayView: View {
    @ObservedObject private var toast = MobileToastManager.shared
    
    public init() {}
    
    public var body: some View {
        Group {
            if let msg = toast.message {
                HStack(spacing: 8) {
                    if let icon = toast.icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95))
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
                .zIndex(9999)
            }
        }
    }
}

// MARK: - Cross-Platform System Colors

extension Color {
    public static var platformSystemBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    public static var platformSecondarySystemBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    public static var platformSystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// MARK: - Offline-First Track Artwork View

public struct TrackArtworkView: View {
    @ObservedObject private var cache = ArtworkImageCache.shared
    let url: URL?
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let placeholderIconSize: CGFloat
    
    public init(
        url: URL?,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 8,
        placeholderIconSize: CGFloat = 16
    ) {
        self.url = url
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.placeholderIconSize = placeholderIconSize
    }
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let side = max(1, min(w, h))
            let isLetterbox = url?.absoluteString.contains("hqdefault.jpg") == true || url?.absoluteString.contains("mqdefault.jpg") == true
            let memImage = cache.image(for: url)
            
            ZStack {
                placeholder(side: side)
                
                #if os(iOS)
                if let uiImage = memImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .scaleEffect(isLetterbox ? 1.35 : 1.0)
                        .frame(width: side, height: side)
                        .clipped()
                }
                #else
                if let nsImage = memImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .scaleEffect(isLetterbox ? 1.35 : 1.0)
                        .frame(width: side, height: side)
                        .clipped()
                }
                #endif
            }
            .frame(width: side, height: side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .position(x: w / 2, y: h / 2)
            .task(id: url) {
                if memImage == nil, let url = url {
                    _ = await cache.loadImage(for: url)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
    
    private func placeholder(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: placeholderIconSize))
                    .foregroundColor(.secondary)
            )
    }
}
