#if canImport(SwiftUI)
import SwiftUI

/// Settings allowing configuration of capture behavior.
struct SettingsView: View {
    /// Toggle for saving the raw camera clip.
    @State private var saveRawClip: Bool
    /// Toggle for using the maximum supported frame rate.
    @State private var useMaxFrameRate: Bool
    /// Toggle controlling whether live HR/HRV metrics are shown on the preview screen.
    @State private var showLiveMetrics: Bool
    /// Toggle controlling whether RMSSD jitter correction is applied.
    @State private var hrvCorrectionEnabled: Bool
    /// Whether to stream live samples to the validation host.
    @State private var streamEnabled: Bool
    /// Hostname or IP of the Mac running ``validation_session.py``.
    @State private var streamHost: String
    /// Port exposed by the WebSocket server on the Mac.
    @State private var streamPort: String
    /// Optional label attached to exported session files.
    @State private var streamTag: String

    init() {
        let defaults = UserDefaults.standard
        _saveRawClip = State(initialValue: defaults.bool(forKey: "saveRawClip"))
        _useMaxFrameRate = State(initialValue: defaults.bool(forKey: "useMaxFrameRate"))
        _showLiveMetrics = State(initialValue: defaults.bool(forKey: "showLiveMetrics"))
        _hrvCorrectionEnabled = State(initialValue: defaults.bool(forKey: "hrvCorrectionEnabled"))
        let config = ValidationStreamConfiguration.load(from: defaults)
        _streamEnabled = State(initialValue: config.isEnabled)
        _streamHost = State(initialValue: config.host)
        _streamPort = State(initialValue: String(config.port))
        _streamTag = State(initialValue: config.sessionTag)
    }

    var body: some View {
        Form {
            Section("Live Feedback") {
                Toggle("Show Live Heart Metrics", isOn: $showLiveMetrics)
                    .onChange(of: showLiveMetrics) {
                        UserDefaults.standard.set(showLiveMetrics, forKey: "showLiveMetrics")
                    }
                Text("When disabled the app only reports heart rate and HRV after a measurement finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Apply HRV timing correction", isOn: $hrvCorrectionEnabled)
                    .onChange(of: hrvCorrectionEnabled) {
                        UserDefaults.standard.set(hrvCorrectionEnabled, forKey: "hrvCorrectionEnabled")
                    }
            }
            Toggle("Save Raw Clip", isOn: $saveRawClip)
                .onChange(of: saveRawClip) {
                    UserDefaults.standard.set(saveRawClip, forKey: "saveRawClip")
                }
            Toggle("Use Maximum Frame Rate", isOn: $useMaxFrameRate)
                .onChange(of: useMaxFrameRate) {
                    UserDefaults.standard.set(useMaxFrameRate, forKey: "useMaxFrameRate")
                }
            Section("Validation Streaming") {
                Toggle("Enable Streaming", isOn: $streamEnabled)
                    .onChange(of: streamEnabled) { _ in persistValidationConfig() }
                TextField("Mac hostname or IP", text: $streamHost)
                    .autocorrectionDisabled(true)
#if canImport(UIKit)
                    .textInputAutocapitalization(.never)
#endif
                    .onChange(of: streamHost) { _ in persistValidationConfig() }
                TextField("Port", text: $streamPort)
                    .autocorrectionDisabled(true)
#if canImport(UIKit)
                    .keyboardType(.numbersAndPunctuation)
#endif
                    .onChange(of: streamPort) { _ in persistValidationConfig() }
                TextField("Session tag", text: $streamTag)
                    .autocorrectionDisabled(true)
                    .onChange(of: streamTag) { _ in persistValidationConfig() }
                Text("The app publishes measurement samples to ws://host:port/rppg. Run validation_session.py on your Mac and ensure both devices share the same network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func persistValidationConfig() {
        var port = Int(streamPort) ?? 8765
        if port <= 0 { port = 8765 }
        let trimmedHost = streamHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = streamTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = ValidationStreamConfiguration(isEnabled: streamEnabled,
                                                   host: trimmedHost,
                                                   port: port,
                                                   sessionTag: trimmedTag)
        config.store()
    }
}

#Preview {
    SettingsView()
}
#endif
