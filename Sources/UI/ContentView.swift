import SwiftUI

/// Main container — tab-based layout matching the web frontend structure.
struct ContentView: View {
    @EnvironmentObject var viewModel: RadioViewModel
    @State private var showStartPrompt = !UserDefaults.standard.bool(forKey: "hasLaunched")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !viewModel.state.powerOn {
                // ── Off state: show startup prompt ──────────────
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("Ham Radio")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)

                    Text("SunSDR2 DX Mobile")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if let err = viewModel.state.connectionError {
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button(action: {
                        UserDefaults.standard.set(true, forKey: "hasLaunched")
                        viewModel.powerOnAsync()
                    }) {
                        HStack {
                            Image(systemName: "power")
                            Text("连接电台")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }

                    Spacer()
                }
            } else {
                // ── On state: main radio UI ─────────────────────
                VStack(spacing: 0) {
                    HeaderView()
                    TabView {
                        MainRXView()
                            .tabItem {
                                Image(systemName: "water.waves")
                                Text("RX")
                            }
                        DSPPanelView()
                            .tabItem {
                                Image(systemName: "slider.horizontal.3")
                                Text("DSP")
                            }
                        SettingsView()
                            .tabItem {
                                Image(systemName: "gearshape")
                                Text("设置")
                            }
                    }
                    .tint(.orange)
                }
            }
        }
    }
}
