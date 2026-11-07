import SwiftUI

/// 10-Band Graphic Equalizer modal sheet for iOS
/// Conforms to Apple Human Interface Guidelines with tactile vertical mixer faders,
/// horizontal preset selector, and frequency response visualization.
public struct MobileEqualizerSheet: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let frequencies = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    private let presets = ["Flat", "Acoustic", "Bass Booster", "Bass Reducer", "Classical", "Electronic", "Hip-Hop", "Jazz", "Pop", "Rock", "Vocal Booster"]
    
    public init() {}
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // 1. Preset Selector Carousel
                    presetChipsSection
                    
                    // 2. Visual Frequency Response Curve
                    frequencyCurveCard
                    
                    // 3. 10-Band Fader Rack
                    bandFadersRack
                    
                    // 4. Quick Audio Reset Action
                    Button {
                        MobileHaptics.trigger(.medium)
                        player.setEqualizerPreset("Flat")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Reset to Flat (0 dB)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $player.isEqualizerEnabled) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .tint(FluidTheme.musicRed)
                    .onChange(of: player.isEqualizerEnabled) { _, _ in
                        MobileHaptics.trigger(.selection)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        MobileHaptics.trigger(.light)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .tint(FluidTheme.musicRed)
                }
            }
            .background(isLight ? Color(UIColor.systemGroupedBackground) : FluidTheme.cardBackground)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
    
    // MARK: - Preset Chips Section
    
    private var presetChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    let isSelected = player.equalizerPreset.lowercased() == preset.lowercased()
                    
                    Button {
                        MobileHaptics.trigger(.selection)
                        player.setEqualizerPreset(preset)
                    } label: {
                        Text(preset)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? FluidTheme.musicRed : (isLight ? Color.white : Color.primary.opacity(0.08)))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Frequency Curve Visualizer
    
    private var frequencyCurveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FREQUENCY RESPONSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                
                Spacer()
                
                Text(player.isEqualizerEnabled ? player.equalizerPreset : "Bypassed")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(player.isEqualizerEnabled ? FluidTheme.musicRed : .secondary)
            }
            
            // Dynamic Waveform / Spectrum Bars
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let bandCount = player.equalizerBands.count
                let colWidth = max(4, (width - CGFloat(bandCount - 1) * 6) / CGFloat(bandCount))
                let zeroY = height / 2
                
                ZStack(alignment: .leading) {
                    // Zero Line (0 dB)
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: width, height: 1)
                        .position(x: width / 2, y: zeroY)
                    
                    // Frequency Columns
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(0..<bandCount, id: \.self) { i in
                            let db = i < player.equalizerBands.count ? player.equalizerBands[i] : 0.0
                            let normalized = CGFloat(db / 12.0) // -1.0 to +1.0
                            let barHeight = max(3, abs(normalized) * (height / 2 - 4))
                            
                            VStack(spacing: 0) {
                                if normalized >= 0 {
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            player.isEqualizerEnabled
                                                ? LinearGradient(colors: [FluidTheme.musicRed, FluidTheme.musicRed.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                                : LinearGradient(colors: [Color.secondary.opacity(0.4), Color.secondary.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                                        )
                                        .frame(width: colWidth, height: barHeight)
                                } else {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            player.isEqualizerEnabled
                                                ? LinearGradient(colors: [FluidTheme.musicRed.opacity(0.7), FluidTheme.musicRed.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                                : LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                                        )
                                        .frame(width: colWidth, height: barHeight)
                                    Spacer()
                                }
                            }
                            .frame(width: colWidth, height: height)
                        }
                    }
                }
            }
            .frame(height: 70)
        }
        .padding(14)
        .background(isLight ? Color.white : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    // MARK: - 10-Band Faders Rack
    
    private var bandFadersRack: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("10-BAND ISO MIXER")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<frequencies.count, id: \.self) { idx in
                        bandFaderColumn(index: idx)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(isLight ? Color.white : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private func bandFaderColumn(index: Int) -> some View {
        let db = index < player.equalizerBands.count ? player.equalizerBands[index] : 0.0
        let freq = frequencies[index]
        
        return VStack(spacing: 8) {
            // Frequency label
            Text(freq)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            
            // Vertical Slider Gestured Fader Track
            ZStack(alignment: .bottom) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 8, height: 130)
                
                // Zero indicator mark
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 14, height: 1)
                    .offset(y: -65)
                
                // Active Fill
                let fillFraction = CGFloat((db + 12.0) / 24.0) // 0.0 to 1.0
                Capsule()
                    .fill(player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: max(6, 130 * fillFraction))
                
                // Fader Knob
                Circle()
                    .fill(isLight ? Color.white : Color(UIColor.systemGray5))
                    .frame(width: 22, height: 22)
                    .shadow(color: Color.black.opacity(0.2), radius: 3, y: 1)
                    .overlay(
                        Circle()
                            .stroke(player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary, lineWidth: 2)
                    )
                    .offset(y: -(130 * fillFraction) + 11)
            }
            .frame(width: 28, height: 130)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let locationY = gesture.location.y
                        let clampedY = max(0, min(130, locationY))
                        let invertedFraction = 1.0 - (clampedY / 130.0) // 0 at bottom, 1 at top
                        var newDb = (invertedFraction * 24.0) - 12.0
                        
                        // Snap to 0 if within 0.7 dB
                        if abs(newDb) < 0.7 {
                            newDb = 0.0
                        }
                        
                        let roundedDb = (round(newDb * 2) / 2) // Round to nearest 0.5 dB
                        if roundedDb != db {
                            MobileHaptics.trigger(.selection)
                            player.setEqualizerBand(index: index, value: roundedDb)
                        }
                    }
            )
            
            // dB Value readout
            Text(db == 0 ? "0" : String(format: "%+.1f", db))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(db != 0 && player.isEqualizerEnabled ? FluidTheme.musicRed : .secondary)
                .frame(width: 34)
        }
    }
}
