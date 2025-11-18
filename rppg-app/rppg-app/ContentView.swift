#if canImport(SwiftUI)
import SwiftUI

/// Root view showing live preview and metrics.
struct ContentView: View {
    @StateObject private var viewModel = PPGViewModel()
    @AppStorage("showLiveMetrics") private var showLiveMetrics: Bool = false

    var body: some View {
        NavigationStack {
            VStack {
                LivePreviewView(session: viewModel.captureSession)
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            ZStack {
                                if let box = viewModel.faceBoundingBox {
                                    let rect = CGRect(
                                        x: box.origin.x * geo.size.width,
                                        y: (1 - box.origin.y - box.height) * geo.size.height,
                                        width: box.width * geo.size.width,
                                        height: box.height * geo.size.height
                                    )
                                    RoundedRectangle(cornerRadius: 12)
                                        .path(in: rect)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                    if let roi = viewModel.roiBoundingBox {
                                        let roiRect = CGRect(
                                            x: roi.origin.x * geo.size.width,
                                            y: (1 - roi.origin.y - roi.height) * geo.size.height,
                                            width: roi.width * geo.size.width,
                                            height: roi.height * geo.size.height
                                        )
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.accentColor.opacity(0.15))
                                            )
                                            .frame(width: roiRect.width, height: roiRect.height)
                                            .position(x: roiRect.midX, y: roiRect.midY)
                                    }

                                }
                                if !viewModel.isStable {
                                    Color.red.opacity(0.4)
                                }
                            }
                        }
                    }
                if showLiveMetrics {
                    MetricsView(
                        vitals: viewModel.vitals,
                        afProbability: viewModel.afProbability,
                        isAFProbabilityAvailable: viewModel.hasComputedAFProbability
                    )
                }
                if viewModel.isMeasuring && viewModel.isStable {
                    LiveWaveformView(waveform: viewModel.waveform)
                        .padding(.top, 4)
                }
                Picker("Window", selection: $viewModel.measurementDuration) {
                    ForEach([15, 20, 30, 45, 60, 90], id: \.self) { value in
                        Text("\(value)s").tag(Double(value))
                    }
                }
                .pickerStyle(.menu)
                .padding(.top, 8)
                .disabled(viewModel.isMeasuring)
                if viewModel.isMeasuring {
                    ProgressView(value: viewModel.measurementProgress)
                        .padding(.top, 8)
                        .animation(.linear, value: viewModel.measurementProgress)
                    Text("Time remaining: \(Int(viewModel.measurementTimeRemaining))s")
                        .padding(.top, 4)
                }
                Button("Start Measuring") {
                    viewModel.startMeasurement()
                }
                .disabled(viewModel.isMeasuring)
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.isMeasuring = false }
            .padding()
            .background(Color("Background").ignoresSafeArea())
            .sheet(item: $viewModel.measurementResult) { result in
                MeasurementResultView(result: result)
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text("Validation Stream"),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: InstructionView()) {
                        Text("I")
                            .font(.headline)
                            .padding(6)
                            .background(
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
#endif
