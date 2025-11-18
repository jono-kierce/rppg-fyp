//
//  rppg_appTests.swift
//  rppg-appTests
//
//  Created by Jonathan Kierce on 27/8/2025.
//

import Foundation
import Testing
@testable import rppg_app
#if canImport(CoreVideo)
import CoreVideo
import CoreGraphics
#endif

struct rppg_appTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func logisticModelProbabilityMatchesFixture() throws {
        let bundle = AFDetector.resourceBundle
        let url = try #require(bundle.url(forResource: "af_logistic_model", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let model = try JSONDecoder().decode(AFLogisticModel.self, from: data)
        let featureMeans = Dictionary(uniqueKeysWithValues: model.features.map { ($0.name, $0.scaleMean) })

        let detector = AFDetector(remote: nil, bundle: bundle)
        let probability = try #require(detector.probability(for: featureMeans))

        let expected = 0.5267504943548451
        #expect(abs(probability - expected) < 1e-9)
    }

    @Test func bandpassFiltersNonPowerOfTwoSampleCounts() throws {
        let sampleRate = 30.0
        let lowFrequency = 0.3
        let passFrequency = 1.0
        let length = 315

        let signal = (0..<length).map { index -> Double in
            let time = Double(index) / sampleRate
            return sin(2 * .pi * lowFrequency * time) + sin(2 * .pi * passFrequency * time)
        }

        let filtered = Filtering.bandpass(
            signal,
            sampleRate: sampleRate,
            lowCut: 0.7,
            highCut: 4.0
        )

        #expect(filtered.count == signal.count)

        let lowBefore = amplitude(of: lowFrequency, in: signal, sampleRate: sampleRate)
        let highBefore = amplitude(of: passFrequency, in: signal, sampleRate: sampleRate)
        let lowAfter = amplitude(of: lowFrequency, in: filtered, sampleRate: sampleRate)
        let highAfter = amplitude(of: passFrequency, in: filtered, sampleRate: sampleRate)

        #expect(lowAfter < lowBefore * 0.6)
        #expect(highAfter > highBefore * 0.5)
        #expect(highAfter > lowAfter)

        let longLength = 4_097
        let longSignal = (0..<longLength).map { index -> Double in
            let time = Double(index) / sampleRate
            return sin(2 * .pi * lowFrequency * time) + sin(2 * .pi * passFrequency * time)
        }

        let longFiltered = Filtering.bandpass(
            longSignal,
            sampleRate: sampleRate,
            lowCut: 0.7,
            highCut: 4.0
        )

        #expect(longFiltered.count == longSignal.count)

        let longLowBefore = amplitude(of: lowFrequency, in: longSignal, sampleRate: sampleRate)
        let longHighBefore = amplitude(of: passFrequency, in: longSignal, sampleRate: sampleRate)
        let longLowAfter = amplitude(of: lowFrequency, in: longFiltered, sampleRate: sampleRate)
        let longHighAfter = amplitude(of: passFrequency, in: longFiltered, sampleRate: sampleRate)

        #expect(longLowAfter < longLowBefore * 0.5)
        #expect(longHighAfter > longHighBefore * 0.5)
        #expect(longHighAfter > longLowAfter)
    }

    @Test func peakDetectionFindsSineMaxima() async throws {
        let sampleRate = 30.0
        let length = 90
        let freq = 1.0
        let signal = (0..<length).map { i in
            sin(2 * .pi * freq * Double(i) / sampleRate)
        }
        let peaks = PeakDetector.detect(in: signal, sampleRate: sampleRate)
        #expect(peaks.count == 3)
        #expect(abs(peaks[0] - 8) <= 1)
        #expect(abs(peaks[1] - 38) <= 1)
        #expect(abs(peaks[2] - 68) <= 1)
    }

    @Test func peakDetectionIgnoresCloseSecondaryPeaks() async throws {
        let sampleRate = 30.0
        let length = 90
        let baseFreq = 1.0
        let noiseFreq = 5.0
        let signal = (0..<length).map { i in
            let t = Double(i) / sampleRate
            return sin(2 * .pi * baseFreq * t) + 0.3 * sin(2 * .pi * noiseFreq * t)
        }
        let peaks = PeakDetector.detect(in: signal, sampleRate: sampleRate)
        #expect(peaks.count == 3)
    }

    @Test func peakDetectionHandlesDecliningAmplitude() async throws {
        let sampleRate = 30.0
        let length = 90
        let freq = 1.0
        let signal = (0..<length).map { i in
            let t = Double(i) / sampleRate
            let amp = 1.0 - 0.7 * Double(i) / Double(length)
            return amp * sin(2 * .pi * freq * t)
        }
        let peaks = PeakDetector.detect(in: signal, sampleRate: sampleRate)
        #expect(peaks.count == 3)
    }

    @Test func peakDetectionAdaptsToAmplitudeDrop() async throws {
        let sampleRate = 30.0
        let length = 90
        let freq = 1.0
        let signal = (0..<length).map { i in
            let t = Double(i) / sampleRate
            let amp = i < length / 2 ? 1.0 : 0.2
            return amp * sin(2 * .pi * freq * t)
        }
        let peaks = PeakDetector.detect(in: signal, sampleRate: sampleRate)
        #expect(peaks.count == 3)
        #expect(abs(peaks[0] - 8) <= 1)
        #expect(abs(peaks[1] - 38) <= 1)
        #expect(abs(peaks[2] - 68) <= 1)
    }

    @Test func peakDetectionSuppressesTWaves() async throws {
        let sampleRate = 30.0
        var signal = [Double](repeating: 0.0, count: 120)
        for offset in [0, 40, 80] {
            signal[offset + 10] = 1.0
            signal[offset + 22] = 0.4
        }
        let peaks = PeakDetector.detect(in: signal, sampleRate: sampleRate)
        #expect(peaks == [10, 50, 90])
    }

    @Test func rmssdCorrectionClampsToZero() {
        let corrected = HRVCorrection.correctedRMSSD(measured: 30)
        #expect(corrected == 0)
    }

    @Test func rmssdCorrectionMatchesPositiveCase() {
        let measured = 120.0
        let corrected = HRVCorrection.correctedRMSSD(measured: measured)
        let expected = sqrt(max(0, measured * measured - 2 * 60.0 * 60.0))
        #expect(abs(corrected - expected) < 1e-9)
    }

#if canImport(CoreVideo)
    @Test func logisticFeatureExtractionProducesExpectedValues() throws {
        let processor = SignalProcessor()
        let timestamps: [Double] = [0, 0.5, 1.0, 1.5, 2.0, 2.5]
        let peaks = [1, 3, 5]
        let chromSignal: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]

        let features = try #require(processor.logisticFeatures(peaks: peaks, timestamps: timestamps, chromSignal: chromSignal))
        let expected: [String: Double] = [
            "mean_rr": 1.0,
            "median_rr": 1.0,
            "std_rr": 0.0,
            "rmssd": 0.0,
            "pnn50": 0.0,
            "hr_mean": 60.0,
            "hr_std": 0.0,
            "num_beats": 3.0,
            "beats_per_second": 1.2,
            "ppg_mean": 0.35,
            "ppg_std": 0.18708286933869706,
        ]

        #expect(features.count == expected.count)
        for (key, value) in expected {
            let actual = try #require(features[key])
            #expect(abs(actual - value) < 1e-9)
        }
    }

    @Test func outlierRemovalMergesDoubleBeats() async throws {
        let ibis: [Double] = [0.102, 0.108, 0.095, 0.045, 0.056, 0.101]
        let (clean, removed) = SignalProcessor.removeDoubleBeatOutliers(ibis)
        #expect(removed == [4])
        #expect(clean.count == 5)
        #expect(abs(clean[3] - 0.101) < 1e-6)
    }

    @Test func outlierRemovalMergesShortLongPairs() async throws {
        let ibis: [Double] = [0.82, 0.78, 0.24, 0.58, 0.79]
        let (clean, removed) = SignalProcessor.removeDoubleBeatOutliers(ibis)
        #expect(removed == [3])
        #expect(clean.count == 4)
        #expect(abs(clean[2] - 0.82) < 1e-6)
    }

    @Test func signalProcessorHandlesConcurrentAccess() async throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = buffer!
        let roi = CGRect(x: 0, y: 0, width: 1, height: 1)
        let processor = SignalProcessor()

        for round in 0..<10 {
            for i in 0..<255 {
                _ = processor.process(pixelBuffer, roi: roi, timestamp: Double(round * 256 + i))
            }
            await withTaskGroup(of: Void.self) { group in
                let ts = Double(round * 256 + 255)
                group.addTask { _ = processor.process(pixelBuffer, roi: roi, timestamp: ts) }
                group.addTask { processor.resetMeasurement() }
                group.addTask { _ = processor.analyzeMeasurement() }
                await group.waitForAll()
            }
        }
    }

    @Test func processClampsRoiAndAverages() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<4 {
            for x in 0..<4 {
                let value = UInt8(y * 4 + x + 1)
                let pixel = base + y * bytesPerRow + x * 4
                pixel[0] = 0
                pixel[1] = 0
                pixel[2] = value
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let processor = SignalProcessor()
        let roi = CGRect(x: 0.75, y: 0.75, width: 0.5, height: 0.5)
        _ = processor.process(pixelBuffer, roi: roi, timestamp: 0)

        let mirror = Mirror(reflecting: processor)
        let rValues = mirror.descendant("rValues") as! [Double]
        #expect(rValues.count == 1)
        #expect(abs(rValues[0] - 4.0 / 255.0) < 1e-6)
    }

    @Test func processMeasurementClampsRoiAndAverages() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<4 {
            for x in 0..<4 {
                let value = UInt8(y * 4 + x + 1)
                let pixel = base + y * bytesPerRow + x * 4
                pixel[0] = 0
                pixel[1] = 0
                pixel[2] = value
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let processor = SignalProcessor()
        let roi = CGRect(x: -0.25, y: 0.75, width: 0.5, height: 0.5)
        _ = processor.processMeasurement(pixelBuffer, roi: roi, timestamp: 0)

        let mirror = Mirror(reflecting: processor)
        let rValues = mirror.descendant("rValues") as! [Double]
        #expect(rValues.count == 1)
        #expect(abs(rValues[0] - 1.0 / 255.0) < 1e-6)
    }
#endif

#if canImport(AVFoundation) && canImport(SwiftUI) && canImport(Combine)
    @Test @MainActor func measurementDurationDefaultsTo30() throws {
        let vm = PPGViewModel()
        #expect(vm.measurementDuration == 30)
    }

    @Test @MainActor func startMeasurementUsesSelectedDuration() async throws {
        let vm = PPGViewModel()
        vm.measurementDuration = 15
        vm.startMeasurement()
        #expect(vm.measurementTimeRemaining == 15)
        vm.isMeasuring = false
    }

    @Test @MainActor func startMeasurementDelaysCountdown() async throws {
        let vm = PPGViewModel()
        vm.startMeasurement()
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(vm.measurementTimeRemaining == vm.measurementDuration)
        vm.isMeasuring = false
    }

    @Test @MainActor func cancelMeasurementResetsTime() throws {
        let vm = PPGViewModel()
        vm.startMeasurement()
        vm.isMeasuring = false
        #expect(vm.measurementTimeRemaining == 0)
    }
#endif

}

private func amplitude(of frequency: Double, in samples: [Double], sampleRate: Double) -> Double {
    guard !samples.isEmpty else { return 0.0 }

    var sumSin = 0.0
    var sumCos = 0.0
    for (index, value) in samples.enumerated() {
        let angle = 2.0 * Double.pi * frequency * Double(index) / sampleRate
        sumSin += value * sin(angle)
        sumCos += value * cos(angle)
    }

    return (2.0 / Double(samples.count)) * sqrt(sumSin * sumSin + sumCos * sumCos)
}
