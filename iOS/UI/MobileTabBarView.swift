import SwiftUI

public enum MobileTab: String, CaseIterable, Identifiable {
    case search = "Search"
    case library = "Library"
    case analytics = "Insights"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .analytics: return "chart.bar.xaxis"
        }
    }
}

/// Floating glass tab bar modeled after Apple Music iOS
public struct MobileTabBarView: View {
    @Binding public var selectedTab: MobileTab
    
    public init(selectedTab: Binding<MobileTab>) {
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        HStack {
            ForEach(MobileTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                    MobileHaptics.trigger(.selection)
                    withAnimation(FluidTheme.fluidSpring) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .symbolVariant(isSelected ? .fill : .none)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 22) // Space for iPhone Home Indicator
        .background(
            Rectangle()
                .fill(FluidTheme.barMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Divider()
                .opacity(0.3),
            alignment: .top
        )
    }
}
