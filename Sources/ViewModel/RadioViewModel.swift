import SwiftUI
import Combine
import AVFoundation

/// Central ViewModel — coordinates networking, audio, and UI state.
@MainActor
final class RadioViewModel: ObservableObject {
    let state = RadioState()
    let connection: ConnectionManager

    let audioPlayback = AudioPlaybackManager()
    let audioCapture = AudioCaptureManager()
    let favorites = FavoritesManager()
    let spectrumProc = SpectrumProcessor()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(serverHost: String = "radio.vlsc.net:8889",
         password: String? = nil) {
        connection = ConnectionManager(serverHost: serverHost, password: password)
        bindSockets()
        // Relay nested ObservableObject changes so SwiftUI re-renders ContentView
        state.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // MARK: - Public API

    private var pingTimer: Timer?
    private let pingInterval: TimeInterval = 2.0

    /// Power on: connect all sockets + start audio session + start heartbeat.
    func powerOn() {
        state.powerOn = true
        connection.connectAll()
        audioPlayback.start()
        startPing()
    }

    /// Async — logs in via API, gets session token, then connects.
    func powerOnAsync() {
        state.powerOn = true
        startPing()

        let scheme = connection.serverHost.contains("localhost") ? "http" : "https"
        guard let loginURL = URL(string: "\(scheme)://\(connection.serverHost)/api/auth/login") else {
            connection.connectAll(); return
        }

        var req = URLRequest(url: loginURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["password": connection.password ?? ""]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Extract token from Set-Cookie header
                var token: String?
                if let httpResp = response as? HTTPURLResponse,
                   httpResp.statusCode == 200,
                   let headerFields = httpResp.allHeaderFields as? [String: String],
                   let url = httpResp.url {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                    token = cookies.first(where: { $0.name == "sunmrrc_auth" })?.value
                    // Also try JSON body fallback
                    if token == nil, let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        token = json["token"] as? String
                    }
                }

                if let tok = token, !tok.isEmpty {
                    self.connection.updateCredentials(password: tok)
                    self.bindSockets()  // re-bind after socket recreation!
                } else {
                    self.state.connectionError = "认证失败，请检查密码"
                }
                self.connection.connectAll()
            }
            Task.detached { [weak self] in
                self?.audioPlayback.start()
            }
        }.resume()
    }

    /// Power off: disconnect + stop audio + stop heartbeat.
    func powerOff() {
        state.powerOn = false
        state.ptt = false
        stopPing()
        connection.disconnectAll()
        audioPlayback.stop()
    }

    // MARK: - Frequency control

    /// Set RX frequency in Hz.
    func setFrequency(_ hz: Int) {
        let clamped = max(100_000, min(2_000_000_000, hz))
        state.frequency = clamped
        connection.sendControl("setFreq:\(clamped)")
    }

    /// Step frequency up or down by `stepHz`.
    func stepFrequency(up: Bool, step: Int = 1000) {
        let delta = up ? step : -step
        setFrequency(state.frequency + delta)
    }

    /// Jump to a predefined band frequency.
    func selectBand(_ hz: Int) {
        setFrequency(hz)
    }

    // MARK: - Filter

    /// Set filter bandwidth by low/high cutoff.
    func setFilter(low: Int, high: Int) {
        state.filterLow = low
        state.filterHigh = high
        connection.sendControl("setFilter:\(low),\(high)")
    }

    /// Set operating mode: USB, LSB, AM, FM, CW, etc.
    func setMode(_ mode: String) {
        state.mode = mode
        connection.sendControl("setMode:\(mode)")
    }

    /// Toggle PTT. Starts mic capture on TX, stops on RX.
    func setPTT(_ tx: Bool) {
        state.ptt = tx
        connection.sendControl("setPTT:\(tx ? "true" : "false")")

        if tx {
            // Send safety fallback "s:" via audioTX channel on PTT release (server: force RX)
            audioCapture.start()
        } else {
            audioCapture.stop()
            // Safety: send "s:" to ensure server drops PTT even if ctrl message lost
            connection.audioTX.send(text: "s:")
        }
    }

    /// Set AF (volume) gain 0.0–1.0.
    func setAFGain(_ gain: Float) {
        state.afGain = gain
        let val = Int(gain * 100)
        connection.sendControl("setAFGain:\(val)")
    }

    /// Set RF gain 0.0–1.0 (maps to 0–100, controls radio front-end gain).
    func setRFGain(_ gain: Float) {
        state.rfGain = gain
        let val = Int(gain * 100)
        connection.sendControl("setRFGain:\(val)")
    }

    /// Set AGC mode: "off", "slow", "medium", "fast".
    func setAGC(_ mode: String) {
        connection.sendControl("setAGC:\(mode)")
    }

    // MARK: - DSP / WDSP

    func setWDSPEnabled(_ on: Bool) {
        state.wdspEnabled = on
        connection.sendControl("setWDSPEnabled:\(on ? "true" : "false")")
    }

    func setNR2Enabled(_ on: Bool) {
        state.nr2Enabled = on
        connection.sendControl("setWDSPNR2:\(on ? "true" : "false")")
    }

    func setNR2Level(_ level: Int) {
        state.nr2Level = level
        connection.sendControl("setWDSPNR2Level:\(level)")
    }

    func setNBEnabled(_ on: Bool) {
        state.nbEnabled = on
        connection.sendControl("setWDSPNB:\(on ? "true" : "false")")
    }

    func setANFEnabled(_ on: Bool) {
        state.anfEnabled = on
        connection.sendControl("setWDSPANF:\(on ? "true" : "false")")
    }

    func setNFEnabled(_ on: Bool) {
        state.nfEnabled = on
        connection.sendControl("setWDSPNFEnabled:\(on ? "true" : "false")")
    }

    func setWDSPAGCMode(_ mode: Int) {
        state.agcMode = mode
        connection.sendControl("setWDSPAGC:\(mode)")
    }

    func setIQSampleRate(_ key: String) {
        connection.sendControl("setSampleRate:\(key)")
    }

    func addNotch(freqHz: Float, bandwidthHz: Float) {
        connection.sendControl("addWDSPNotch:\(freqHz),\(bandwidthHz)")
    }

    func deleteNotch(index: Int) {
        connection.sendControl("deleteWDSPNotch:\(index)")
    }

    // MARK: - Private

    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.state.powerOn,
                      self.connection.ctrlConnected else { return }
                self.state.lastPingTime = .now
                self.connection.sendControl("PING")
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func bindSockets() {
        // ── Error forwarding ───────────────────────────────────
        connection.ctrl.onError = { [weak self] err in
            Task { @MainActor [weak self] in
                self?.state.connectionError = err.localizedDescription
            }
        }

        // ── Control text messages ──────────────────────────────
        connection.ctrl.onText = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state.apply(serverMessage: text)
                self.state.ctrlConnected = self.connection.ctrlConnected
            }
        }

        // ── Audio RX binary → playback ────────────────────────
        connection.audioRX.onBinary = { [weak self] data in
            self?.audioPlayback.enqueue(int16Data: data)
        }

        // ── Mic capture → TX WebSocket ────────────────────────
        audioCapture.onFrame = { [weak self] pcmData in
            self?.connection.audioTX.send(binary: pcmData)
        }

        // ── Spectrum → SpectrumProcessor (off-main-thread) ──
        var specCount = 0
        connection.spectrum.onBinary = { [weak self] data in
            specCount += 1
            if specCount % 100 == 0 {
                print("🌊 Spectrum frames: \(specCount), last=\(data.count) bytes")
            }
            // Feed to background processor; it calls back on main with final UIImage
            self?.spectrumProc.feed(data: data) { img in
                self?.state.waterfallImage = img
            }
        }
    }
}
