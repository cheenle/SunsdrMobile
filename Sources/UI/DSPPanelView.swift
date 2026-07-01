import SwiftUI

/// WDSP control panel with notch visualization, NR meter, and recording.
struct DSPPanelView: View {
    @EnvironmentObject var viewModel: RadioViewModel
    @State private var notchFreq: String = "1000"
    @State private var notchBW: String = "100"
    @State private var showShareSheet = false
    @State private var recordedWAV: Data?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // ── WDSP Master + Recording ────────────────────────
                HStack {
                    Toggle("WDSP", isOn: Binding(
                        get: { viewModel.state.wdspEnabled },
                        set: { viewModel.setWDSPEnabled($0) }
                    ))
                    .tint(.orange)
                    .font(.subheadline.weight(.medium))

                    Spacer()

                    // Record button
                    Button(action: {
                        let ap = viewModel.audioPlayback
                        if ap.isRecording {
                            recordedWAV = ap.stopRecording()
                            if recordedWAV != nil { showShareSheet = true }
                        } else {
                            ap.startRecording()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(viewModel.audioPlayback.isRecording ? Color.red : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(viewModel.audioPlayback.isRecording
                                 ? String(format: "%.1fs", viewModel.audioPlayback.recordingDuration)
                                 : "录音")
                                .font(.subheadline.monospaced())
                        }
                        .foregroundColor(viewModel.audioPlayback.isRecording ? .red : .gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.audioPlayback.isRecording
                                    ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $showShareSheet) {
                        if let wav = recordedWAV {
                            ShareSheet(items: [wav])
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // ── Notch visualization chart ──────────────────────
                NotchChartView(
                    notches: viewModel.state.notches,
                    filterLow: viewModel.state.filterLow,
                    filterHigh: viewModel.state.filterHigh,
                    maxFreq: 5000
                )
                .frame(height: 60)
                .padding(.horizontal, 16)

                // ── NR2 card ───────────────────────────────────────
                GroupBox(label: Label("NR2 降噪", systemImage: "waveform.and.magnifyingglass")) {
                    VStack(spacing: 8) {
                        Toggle("启用", isOn: Binding(
                            get: { viewModel.state.nr2Enabled },
                            set: { viewModel.setNR2Enabled($0) }
                        ))
                        .tint(.orange)

                        if viewModel.state.nr2Enabled {
                            HStack {
                                Text("强度")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Slider(value: Binding(
                                    get: { Double(viewModel.state.nr2Level) },
                                    set: { viewModel.setNR2Level(Int($0)) }
                                ), in: 0...100, step: 1)
                                .tint(.orange)
                                Text("\(viewModel.state.nr2Level)")
                                    .font(.subheadline.monospaced())
                                    .frame(width: 30)
                                    .foregroundColor(.orange)
                            }

                            // NR level meter
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(nrMeterColor)
                                        .frame(width: CGFloat(viewModel.state.nr2Level) / 100 * geo.size.width, height: 6)
                                        .animation(.easeOut(duration: 0.3), value: viewModel.state.nr2Level)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .groupBoxStyle(DarkGroupBoxStyle())

                // ── Noise processing card ──────────────────────────
                GroupBox(label: Label("噪声处理", systemImage: "ear.badge.waveform")) {
                    VStack(spacing: 4) {
                        ToggleRow("NB 噪声消除", isOn: Binding(
                            get: { viewModel.state.nbEnabled },
                            set: { viewModel.setNBEnabled($0) }
                        ))
                        ToggleRow("ANF 自动陷波", isOn: Binding(
                            get: { viewModel.state.anfEnabled },
                            set: { viewModel.setANFEnabled($0) }
                        ))
                        ToggleRow("NF 陷波滤波", isOn: Binding(
                            get: { viewModel.state.nfEnabled },
                            set: { viewModel.setNFEnabled($0) }
                        ))
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .groupBoxStyle(DarkGroupBoxStyle())

                // ── AGC card ───────────────────────────────────────
                GroupBox(label: Label("AGC 自动增益", systemImage: "dial.low")) {
                    HStack(spacing: 0) {
                        ForEach(["关", "慢", "中", "快"].indices, id: \.self) { i in
                            Button(action: { viewModel.setWDSPAGCMode(i) }) {
                                Text(["关", "慢", "中", "快"][i])
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(viewModel.state.agcMode == i ? .black : .orange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(viewModel.state.agcMode == i ? Color.orange : Color.clear)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .groupBoxStyle(DarkGroupBoxStyle())

                // ── Notch list card ────────────────────────────────
                GroupBox(label: Label("陷波器", systemImage: "scissors")) {
                    VStack(spacing: 6) {
                        // Add row
                        HStack(spacing: 6) {
                            TextField("Hz", text: $notchFreq)
                                .keyboardType(.numberPad)
                                .font(.subheadline.monospaced())
                                .foregroundColor(.orange)
                            TextField("BW", text: $notchBW)
                                .keyboardType(.numberPad)
                                .font(.subheadline.monospaced())
                                .foregroundColor(.orange)
                            Button("添加") {
                                guard let f = Float(notchFreq), let b = Float(notchBW), f > 0 else { return }
                                viewModel.addNotch(freqHz: f, bandwidthHz: b)
                                notchFreq = ""; notchBW = ""
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange)
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        }

                        if viewModel.state.notches.isEmpty {
                            Text("无陷波器 — 添加以消除干扰")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            ForEach(viewModel.state.notches) { notch in
                                HStack {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text("\(Int(notch.freqHz)) Hz")
                                        .font(.subheadline.monospaced())
                                    Text("±\(Int(notch.bandwidthHz))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Button(role: .destructive) {
                                        viewModel.deleteNotch(index: notch.index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .groupBoxStyle(DarkGroupBoxStyle())

                Spacer(minLength: 20)
            }
        }
        .background(Color.black)
    }

    private var nrMeterColor: Color {
        let lvl = viewModel.state.nr2Level
        switch lvl {
        case 0..<30:  return .blue
        case 30..<70: return .orange
        default:      return .red
        }
    }
}

// MARK: - Notch Chart

struct NotchChartView: View {
    let notches: [WDSPNotch]
    let filterLow: Int
    let filterHigh: Int
    let maxFreq: Int  // Hz — top of chart

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))

                    // Filter passband
                    let lowFrac = CGFloat(filterLow) / CGFloat(maxFreq)
                    let highFrac = CGFloat(filterHigh) / CGFloat(maxFreq)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.2))
                        .frame(width: (highFrac - lowFrac) * geo.size.width,
                               height: geo.size.height)
                        .offset(x: lowFrac * geo.size.width)

                    // Notch markers
                    ForEach(notches) { notch in
                        let x = CGFloat(notch.freqHz) / CGFloat(maxFreq) * geo.size.width
                        let halfBW = CGFloat(notch.bandwidthHz) / CGFloat(maxFreq) * geo.size.width / 2

                        Rectangle()
                            .fill(Color.red.opacity(0.7))
                            .frame(width: max(halfBW * 2, 3), height: geo.size.height)
                            .offset(x: x - halfBW)
                    }

                    // Center line
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: geo.size.height)
                        .offset(x: geo.size.width / 2)
                }
            }

            // Frequency labels
            HStack(spacing: 0) {
                Text("0")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(maxFreq / 2000)k")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(maxFreq / 1000)k")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Helper views

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .tint(.orange)
            .font(.subheadline)
    }
}

struct DarkGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            configuration.content
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Share Sheet (for exporting WAV)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

