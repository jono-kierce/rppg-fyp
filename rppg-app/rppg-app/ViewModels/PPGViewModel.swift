#if canImport(AVFoundation) && canImport(SwiftUI) && canImport(Combine)
import Combine
import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// ViewModel coordinating camera frames and signal processing.
@MainActor
final class PPGViewModel: ObservableObject {
    @Published var isStable: Bool = true
    @Published var vitals: VitalSigns?
    @Published var faceBoundingBox: CGRect?
    @Published var roiBoundingBox: CGRect?
    @Published var alert: MeasurementAlert?
    @Published var isMeasuring: Bool = false {
        didSet {
            let wasMeasuring = oldValue
            if !isMeasuring {
                if wasMeasuring && !isEndingMeasurement {
                    Task { await validationStreamer.cancelMeasurement() }
                }
                measurementStartTime = nil
                measurementTimeRemaining = 0
                measurementProgress = 0
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
            }
        }
    }
    /// Selected measurement window in seconds.
    @Published var measurementDuration: Double = 30
    /// Seconds remaining in the current measurement countdown.
    @Published var measurementTimeRemaining: Double = 0
    /// Progress from 0 to 1 during the current measurement.
    @Published var measurementProgress: Double = 0
    /// Analysis result produced after a completed measurement.
    @Published var measurementResult: SignalAnalysis?
    /// Band-passed waveform samples for live preview.
    @Published var waveform = Waveform(samples: [], index: 0)
    /// Latest AF detection probability produced after a measurement.
    @Published var afProbability: Double?
    /// Tracks whether the AF probability corresponds to the most recent measurement attempt.
    @Published var hasComputedAFProbability: Bool = false

    private let camera = CameraManager()
    /// Exposes the camera's capture session for preview rendering.
    var captureSession: AVCaptureSession { camera.session }
    /// Duration of the live waveform displayed during preview.
    private let waveformDuration: Double = 12
    private let processor: SignalProcessor
    private let motion = MotionEvaluator()
    private let validationStreamer = ValidationStreamManager()
    private var cancellables = Set<AnyCancellable>()
    private var exposureLocked = false
    /// Warm-up timestamp before measurement frames are processed.
    private var measurementStartTime: Date?
    /// Delay inserted after tapping start to reduce capture noise.
    private let warmupDelay: TimeInterval = 1
    /// Prevents starting the camera pipeline multiple times.
    private var hasStarted = false
    private var isEndingMeasurement = false

    struct MeasurementAlert: Identifiable {
        let id = UUID()
        let message: String
    }

    init() {
        processor = SignalProcessor(waveformDuration: waveformDuration)
        processor.waveformPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$waveform)
    }

    /// Start the capture and processing pipeline.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        camera.framePublisher
            .map { [weak self] data -> (CVPixelBuffer, CGRect?, Double) in
                let (buffer, timestamp) = data
                guard let self else { return (buffer, nil, timestamp) }
                let result = self.motion.evaluate(buffer)
                if !self.exposureLocked && result.roiBoundingBox != nil {
                    self.camera.freezeAutoExposureAndWhiteBalance()
                    self.exposureLocked = true
                }
                DispatchQueue.main.async {
                    self.isStable = result.isStable
                    self.faceBoundingBox = result.faceBoundingBox
                    self.roiBoundingBox = result.roiBoundingBox
                }
                return (buffer, result.roiBoundingBox, timestamp)
            }
            .compactMap { [weak self] data in
                let (buffer, roi, timestamp) = data
                guard let self else { return nil }
                if self.isMeasuring,
                   let start = self.measurementStartTime,
                   Date() >= start {
                    return self.processor.processMeasurement(buffer, roi: roi, timestamp: timestamp)
                } else {
                    return self.processor.process(buffer, roi: roi, timestamp: timestamp)
                }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$vitals)

        camera.startSession()
    }

    /// Begin a measurement session lasting ``measurementDuration`` seconds.
    ///
    /// The actual frame collection is delayed by one second to allow the
    /// camera to settle after the user taps the screen. During the session the
    /// device's idle timer is disabled to keep the display awake.
    func startMeasurement() {
        guard !isMeasuring else { return }
        processor.resetMeasurement()
        measurementTimeRemaining = measurementDuration
        measurementProgress = 0
        measurementStartTime = Date().addingTimeInterval(warmupDelay)
        isMeasuring = true
        afProbability = nil
        hasComputedAFProbability = false
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.warmupDelay * 1_000_000_000))
            guard self.isMeasuring else { return }
            do {
                try await self.validationStreamer.beginMeasurement(duration: self.measurementDuration)
            } catch {
                await MainActor.run {
                    self.isMeasuring = false
                    self.alert = MeasurementAlert(
                        message: "The validation server is unreachable. You can disable streaming in Settings."
                    )
                }
                return
            }
            let startDate = Date()
            while self.isMeasuring {
                let elapsed = Date().timeIntervalSince(startDate)
                await MainActor.run {
                    self.measurementTimeRemaining = max(0, self.measurementDuration - elapsed)
                    self.measurementProgress = min(1, elapsed / self.measurementDuration)
                }
                if elapsed >= self.measurementDuration {
                    await MainActor.run { self.finishMeasurement() }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func finishMeasurement() {
        isEndingMeasurement = true
        isMeasuring = false
        Task.detached { [weak self] in
            guard let self else { return }
            _ = self.processor.analyzeMeasurement()
            let result = self.processor.lastAnalysis
            await self.validationStreamer.finishMeasurement(result: result)
            await MainActor.run {
                self.measurementResult = result
                self.afProbability = result?.afProbability
                self.hasComputedAFProbability = true
                self.isEndingMeasurement = false
            }
        }
    }

    deinit {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        Task { await validationStreamer.shutdown() }
    }
}
#endif
