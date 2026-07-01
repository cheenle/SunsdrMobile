import SwiftUI

/// Primary RX tab: S-meter + waterfall + audio/filter controls + mode + PTT.
struct MainRXView: View {
    @EnvironmentObject var viewModel: RadioViewModel

    // Preset filter bandwidths (Hz, as string labels)
    private let filterPresets: [(label: String, low: Int, high: Int)] = [
        ("CW",   400,  800),
        ("SSB",  300, 2700),
        ("Wide", 100, 4000),
        ("AM",   100, 6000),
        ("FM",   100, 8000),
    ]

    var body: some View {
        VStack(spacing: 6) {
            // ── S-meter ─────────────────────────────────────────
            SMeterView(level: viewModel.state.signalLevel, ptt: viewModel.state.ptt)

            // ── Waterfall ───────────────────────────────────────
            WaterfallView(
                waterfallImage: viewModel.state.waterfallImage,
                rxFrequency: viewModel.state.frequency,
                iqSampleRateHz: viewModel.state.iqSampleRateHz,
                onTapFrequency: { hz in viewModel.setFrequency(hz) }
            )
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // ── Audio level bar + mute ──────────────────────────
            HStack(spacing: 8) {
                Button(action: { viewModel.audioPlayback.isMuted.toggle() }) {
                    Image(systemName: viewModel.audioPlayback.isMuted
                          ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.audioPlayback.isMuted ? .red : .green)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(audioLevelColor)
                            .frame(width: max(2, CGFloat(viewModel.audioPlayback.rmsLevel * 3) * geo.size.width), height: 14)
                            .animation(.easeOut(duration: 0.1), value: viewModel.audioPlayback.rmsLevel)
                    }
                }
                .frame(height: 14)

                Text(String(format: "%.0f", viewModel.audioPlayback.rmsLevel * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 22)
            }
            .padding(.horizontal, 16)

            // ── AF / RF / SQL gain sliders ──────────────────────
            HStack(spacing: 10) {
                GainSlider(label: "AF", value: Binding(
                    get: { Double(viewModel.state.afGain) },
                    set: { viewModel.setAFGain(Float($0)) }
                ), tint: .green)

                GainSlider(label: "RF", value: Binding(
                    get: { Double(viewModel.state.rfGain) },
                    set: { viewModel.setRFGain(Float($0)) }
                ), tint: .orange)

                GainSlider(label: "SQL", value: Binding(
                    get: { Double(viewModel.state.squelch) },
                    set: { viewModel.state.squelch = Float($0) }
                ), tint: .blue)
            }
            .padding(.horizontal, 16)

            Divider().background(Color.orange.opacity(0.3)).padding(.horizontal, 16)

            // ── Mode + Filter — one row ──────────────────────────
            HStack(spacing: 16) {
                ModeSelectorView(
                    currentMode: viewModel.state.mode,
                    onSelect: { viewModel.setMode($0) }
                )

                FilterSelectorView(
                    currentLabel: currentFilterLabel,
                    onSelect: { preset in
                        viewModel.setFilter(low: preset.low, high: preset.high)
                    }
                )
            }
            .padding(.horizontal, 16)

            // ── Channel memories 3×3 grid ────────────────────────
            let mems = Array(viewModel.favorites.channels.prefix(9))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<9, id: \.self) { i in
                    if i < mems.count {
                        let ch = mems[i]
                        Button(action: {
                            viewModel.setFrequency(ch.frequency)
                            viewModel.setMode(ch.mode)
                        }) {
                            VStack(spacing: 2) {
                                Text(ch.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                Text(ch.freqString)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(6)
                        }
                    } else {
                        // Placeholder empty cell
                        VStack(spacing: 2) {
                            Text("---")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("---.---")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.2))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 16)

            Divider().background(Color.orange.opacity(0.3)).padding(.horizontal, 16)

            // ── PTT ──────────────────────────────────────────────
            HStack(spacing: 12) {
                Spacer()

                if viewModel.state.ptt {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 20)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(txLevelColor)
                                .frame(width: max(2, CGFloat(viewModel.audioCapture.txLevel * 5) * geo.size.width), height: 20)
                                .animation(.easeOut(duration: 0.1), value: viewModel.audioCapture.txLevel)
                        }
                    }
                    .frame(width: 50, height: 20)
                }

                PTTButtonView(
                    ptt: viewModel.state.ptt,
                    onPress: { viewModel.setPTT(true) },
                    onRelease: { viewModel.setPTT(false) }
                )

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.black)
    }

    private var currentFilterLabel: String {
        filterPresets.first(where: {
            $0.low == viewModel.state.filterLow && $0.high == viewModel.state.filterHigh
        })?.label ?? "SSB"
    }

    private var audioLevelColor: Color {
        let lvl = viewModel.audioPlayback.rmsLevel * 3
        switch lvl {
        case 0..<0.3:  return .green
        case 0.3..<0.7: return .yellow
        default:        return .red
        }
    }

    private var txLevelColor: Color {
        let lvl = viewModel.audioCapture.txLevel * 5
        switch lvl {
        case 0..<0.3:  return .green
        case 0.3..<0.7: return .yellow
        default:        return .red
        }
    }
}

// MARK: - Mini gain slider

struct GainSlider: View {
    let label: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
            Slider(value: $value, in: 0...1)
                .tint(tint)
                .scaleEffect(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Selector (rotary)

struct FilterSelectorView: View {
    let currentLabel: String
    let onSelect: ((label: String, low: Int, high: Int)) -> Void

    private let presets: [(label: String, low: Int, high: Int)] = [
        ("CW",   400,  800),
        ("SSB",  300, 2700),
        ("Wide", 100, 4000),
        ("AM",   100, 6000),
        ("FM",   100, 8000),
    ]

    private var currentIndex: Int {
        presets.firstIndex(where: { $0.label == currentLabel }) ?? 1
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { select(offset: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 4)

            Button(action: { select(offset: 1) }) {
                Text(currentLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
                    .frame(minWidth: 32)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
            }

            Button(action: { select(offset: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 4)
        }
    }

    private func select(offset: Int) {
        var idx = (currentIndex + offset) % presets.count
        if idx < 0 { idx += presets.count }
        onSelect(presets[idx])
    }
}
