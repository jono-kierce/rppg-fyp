#if canImport(CoreVideo)
import CoreVideo
import CoreGraphics
import Dispatch
import Combine
import Foundation

/// Performs rPPG signal extraction and computes vital signs.
final class SignalProcessor {
    private var rValues: [Double] = []
    private var gValues: [Double] = []
    private var bValues: [Double] = []
    private var timestamps: [Double] = []

    /// Ring buffer of band-passed samples for live waveform rendering.
    private var waveform = Waveform(samples: [], index: 0)
    /// Number of samples displayed in the live waveform (derived from `waveformDuration` at 30 Hz).
    private let waveformWindow: Int
    private var smoothingBuffer: [Double] = []
    private let waveformSubject = CurrentValueSubject<Waveform, Never>(Waveform(samples: [], index: 0))
    /// Publisher streaming the latest band-passed waveform samples.
    var waveformPublisher: AnyPublisher<Waveform, Never> {
        waveformSubject.eraseToAnyPublisher()
    }

    /// Last computed vital signs so they can persist between calculations.
    private var lastVitals: VitalSigns?
    /// Last full-signal analysis result for measurement sessions.
    private(set) var lastAnalysis: SignalAnalysis?
    /// Helper providing atrial fibrillation probabilities using the logistic model.
    private let afDetector: AFDetector

    /// Serial queue protecting access to collected samples and analysis results.
    private let dataQueue = DispatchQueue(label: "SignalProcessor.data")
    /// Serial queue ensuring heavy analysis runs in the background without overlap.
    private let analysisQueue = DispatchQueue(label: "SignalProcessor.analysis")

    private let windowSize = 256
    /// Create a processor.
    /// - Parameter waveformDuration: Duration of the live waveform in seconds.
    init(waveformDuration: Double = 12, afDetector: AFDetector = AFDetector()) {
        self.waveformWindow = Int(waveformDuration * 30)
        self.waveform = Waveform(samples: [], index: 0)
        self.afDetector = afDetector
    }


    /// Process a frame and return the latest vital signs when available.
    /// - Parameters:
    ///   - pixelBuffer: Input video frame.
    ///   - roi: Normalized region of interest in Vision coordinates (origin bottom-left).
    ///   - timestamp: Presentation timestamp of the frame in seconds.
    /// - Returns: Most recent `VitalSigns`, updated every `windowSize` samples.
    func process(_ pixelBuffer: CVPixelBuffer, roi: CGRect?, timestamp: Double) -> VitalSigns? {
        guard let roi else { return dataQueue.sync { lastVitals } }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Convert normalized Vision coordinates (origin bottom-left) to pixel bounds
        // and clamp to the pixel buffer.
        var roiX = Int(roi.origin.x * CGFloat(width))
        var roiY = Int((1 - roi.origin.y - roi.size.height) * CGFloat(height))
        var roiWidth = Int(roi.size.width * CGFloat(width))
        var roiHeight = Int(roi.size.height * CGFloat(height))

        if roiX < 0 {
            roiWidth += roiX
            roiX = 0
        }
        if roiY < 0 {
            roiHeight += roiY
            roiY = 0
        }
        if roiX + roiWidth > width {
            roiWidth = width - roiX
        }
        if roiY + roiHeight > height {
            roiHeight = height - roiY
        }
        guard roiWidth > 0, roiHeight > 0 else {
            return dataQueue.sync { lastVitals }
        }

        var rSum = 0.0, gSum = 0.0, bSum = 0.0
        let buffer = base.assumingMemoryBound(to: UInt8.self)

        for y in roiY..<roiY + roiHeight {
            let row = buffer + y * bytesPerRow
            for x in roiX..<roiX + roiWidth {
                let pixel = row + x * 4 // BGRA format
                bSum += Double(pixel[0])
                gSum += Double(pixel[1])
                rSum += Double(pixel[2])
            }
        }

        let count = Double(roiWidth * roiHeight)
        let r = rSum / count / 255.0
        let g = gSum / count / 255.0
        let b = bSum / count / 255.0
        // 2. Append color channel averages.
        let snapshot = dataQueue.sync { () -> ([Double], [Double], [Double], [Double], VitalSigns?) in
            rValues.append(r)
            gValues.append(g)
            bValues.append(b)
            timestamps.append(timestamp)
            return (rValues, gValues, bValues, timestamps, lastVitals)
        }

        // 3. Process when enough samples collected.
        guard snapshot.0.count >= windowSize else { return snapshot.4 }

        let rWindow = Array(snapshot.0.suffix(windowSize))
        let gWindow = Array(snapshot.1.suffix(windowSize))
        let bWindow = Array(snapshot.2.suffix(windowSize))
        let tWindow = Array(snapshot.3.suffix(windowSize))

        let duration = tWindow.last! - tWindow.first!
        let sampleRate = duration > 0 ? Double(windowSize - 1) / duration : 30.0

        // Normalize channels.
        let nr = normalize(rWindow)
        let ng = normalize(gWindow)
        let nb = normalize(bWindow)

        // 4. Chrominance projection (CHROM method).
        var x = [Double](repeating: 0, count: windowSize)
        var y = [Double](repeating: 0, count: windowSize)
        for i in 0..<windowSize {
            x[i] = 3 * nr[i] - 2 * ng[i]
            y[i] = 1.5 * nr[i] + ng[i] - 1.5 * nb[i]
        }
        let alpha = std(x) / std(y)
        let s = zip(x, y).map { $0 - alpha * $1 }

        // 5. Bandpass filter.
        let filtered = Filtering.bandpass(s, sampleRate: sampleRate)
        if let sample = filtered.last {
            publishWaveformSample(sample)
        }

        // 6. Peak detection for time-domain HR and HRV.
        let peaks = PeakDetector.detect(in: filtered, sampleRate: sampleRate)

        var ibis: [Double] = []
        if peaks.count >= 2 {
            for i in 1..<peaks.count {
                let dt = tWindow[peaks[i]] - tWindow[peaks[i - 1]]
                ibis.append(dt)
            }
        }
        let (cleanIbis, _) = Self.removeDoubleBeatOutliers(ibis)
        let avgIbi = mean(cleanIbis)
        let timeDomainHR = avgIbi > 0 ? 60.0 / avgIbi : 0.0
        let hrvMeasured = rmssd(cleanIbis) // ms after scaling successive IBI differences.
        let hrvCorrected = HRVCorrection.correctedRMSSD(measured: hrvMeasured) // sqrt(max(0, RMSSD_meas^2 - 2σ^2)).

        // 7. FFT for frequency-domain HR estimate.
        let spectrum = Filtering.fft(filtered)

        // 8. Dominant frequency -> heart rate.
        let freqResolution = sampleRate / Double(windowSize)
        let lowCut = 0.7
        let highCut = 4.0
        let lowIndex = Int(lowCut / freqResolution)
        let highIndex = min(Int(highCut / freqResolution), spectrum.count - 1)
        var maxIndex = lowIndex
        var maxValue = spectrum[lowIndex]
        if highIndex > lowIndex {
            for i in lowIndex...highIndex where spectrum[i] > maxValue {
                maxValue = spectrum[i]
                maxIndex = i
            }
        }
        let hrFrequency = Double(maxIndex) * freqResolution
        let freqHeartRate = hrFrequency * 60.0

        // 9. Prefer time-domain HR when available.
        let heartRate = timeDomainHR > 0 ? timeDomainHR : freqHeartRate

        // Maintain sliding window.
        let vitals = VitalSigns(heartRate: heartRate, hrvCorrected: hrvCorrected, hrvMeasured: hrvMeasured)
        dataQueue.sync {
            let removeCount = min(windowSize / 2, rValues.count, gValues.count, bValues.count, timestamps.count)
            if removeCount > 0 {
                rValues.removeFirst(removeCount)
                gValues.removeFirst(removeCount)
                bValues.removeFirst(removeCount)
                timestamps.removeFirst(removeCount)
            }
            lastVitals = vitals
        }
        return vitals
    }

    /// Remove all collected samples and previous measurement results.
    func resetMeasurement() {
        dataQueue.sync {
            rValues.removeAll()
            gValues.removeAll()
            bValues.removeAll()
            timestamps.removeAll()
            lastAnalysis = nil
            lastVitals = nil
            waveform = Waveform(samples: [], index: 0)
            smoothingBuffer.removeAll()
            waveformSubject.send(waveform)
        }
    }

    /// Process a frame accumulating all samples since `resetMeasurement()`.
    /// - Note: Unlike `process`, this function retains all samples for the
    ///   duration of the measurement session. Heavy analysis of the accumulated
    ///   signal is performed separately via `analyzeMeasurement()` to avoid
    ///   blocking the capture pipeline.
    func processMeasurement(_ pixelBuffer: CVPixelBuffer, roi: CGRect?, timestamp: Double) -> VitalSigns? {
        let currentVitals = dataQueue.sync { lastAnalysis?.vitals }
        guard let roi else { return currentVitals }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var roiX = Int(roi.origin.x * CGFloat(width))
        var roiY = Int((1 - roi.origin.y - roi.size.height) * CGFloat(height))
        var roiWidth = Int(roi.size.width * CGFloat(width))
        var roiHeight = Int(roi.size.height * CGFloat(height))

        if roiX < 0 {
            roiWidth += roiX
            roiX = 0
        }
        if roiY < 0 {
            roiHeight += roiY
            roiY = 0
        }
        if roiX + roiWidth > width {
            roiWidth = width - roiX
        }
        if roiY + roiHeight > height {
            roiHeight = height - roiY
        }
        guard roiWidth > 0, roiHeight > 0 else { return currentVitals }

        var rSum = 0.0, gSum = 0.0, bSum = 0.0
        let buffer = base.assumingMemoryBound(to: UInt8.self)

        for y in roiY..<roiY + roiHeight {
            let row = buffer + y * bytesPerRow
            for x in roiX..<roiX + roiWidth {
                let pixel = row + x * 4
                bSum += Double(pixel[0])
                gSum += Double(pixel[1])
                rSum += Double(pixel[2])
            }
        }

        let count = Double(roiWidth * roiHeight)
        let r = rSum / count / 255.0
        let g = gSum / count / 255.0
        let b = bSum / count / 255.0
        dataQueue.sync {
            rValues.append(r)
            gValues.append(g)
            bValues.append(b)
            timestamps.append(timestamp)
        }

        analysisQueue.async { [weak self] in
            self?.updateWaveform()
        }

        return currentVitals
    }

    /// Analyze the accumulated samples and update `lastAnalysis`.
    /// - Returns: Latest `VitalSigns` if analysis succeeds.
    func analyzeMeasurement() -> VitalSigns? {
        return analysisQueue.sync {
            let snapshot = dataQueue.sync { (rValues, gValues, bValues, timestamps) }
            let rWindow = snapshot.0
            let gWindow = snapshot.1
            let bWindow = snapshot.2
            let tWindow = snapshot.3
            guard rWindow.count >= windowSize else { return lastAnalysis?.vitals }

            let duration = tWindow.last! - tWindow.first!
            let sampleRate = duration > 0 ? Double(rWindow.count - 1) / duration : 30.0

            let nr = normalize(rWindow)
            let ng = normalize(gWindow)
            let nb = normalize(bWindow)

            var x = [Double](repeating: 0, count: rWindow.count)
            var y = [Double](repeating: 0, count: rWindow.count)
            for i in 0..<rWindow.count {
                x[i] = 3 * nr[i] - 2 * ng[i]
                y[i] = 1.5 * nr[i] + ng[i] - 1.5 * nb[i]
            }
            let alpha = std(x) / std(y)
            let chromSignal = zip(x, y).map { $0 - alpha * $1 }

            let filtered = Filtering.bandpass(chromSignal, sampleRate: sampleRate)

            let peaks = PeakDetector.detect(in: filtered, sampleRate: sampleRate)

            var ibis: [Double] = []
            if peaks.count >= 2 {
                for i in 1..<peaks.count {
                    let dt = tWindow[peaks[i]] - tWindow[peaks[i - 1]]
                    ibis.append(dt)
                }
            }
            let rawAvgIbi = mean(ibis)
            let rawHR = rawAvgIbi > 0 ? 60.0 / rawAvgIbi : 0.0
            let rawHrvMeasured = rmssd(ibis) // ms using unfiltered inter-beat intervals.
            let rawHrvCorrected = HRVCorrection.correctedRMSSD(measured: rawHrvMeasured) // sqrt(max(0, RMSSD_meas^2 - 2σ^2)).
            let (cleanIbis, removedIndices) = Self.removeDoubleBeatOutliers(ibis)
            let outlierPeaks = removedIndices.map { peaks[$0] }
            let removed = removedIndices.count
            let avgIbi = mean(cleanIbis)
            let timeDomainHR = avgIbi > 0 ? 60.0 / avgIbi : 0.0
            let hrvMeasured = rmssd(cleanIbis) // ms after removing double-beat outliers.
            let hrvCorrected = HRVCorrection.correctedRMSSD(measured: hrvMeasured) // sqrt(max(0, RMSSD_meas^2 - 2σ^2)).

            let fftCount = 1 << Int(log2(Double(filtered.count)))
            var freqHeartRate = 0.0
            if fftCount >= 2 {
                let fftSignal = Array(filtered.suffix(fftCount))
                let spectrum = Filtering.fft(fftSignal)
                if !spectrum.isEmpty {
                    let freqResolution = sampleRate / Double(fftSignal.count)
                    let lowCut = 0.7
                    let highCut = 4.0
                    let lowIndex = Int(lowCut / freqResolution)
                    let highIndex = min(Int(highCut / freqResolution), spectrum.count - 1)
                    if lowIndex < spectrum.count && highIndex >= lowIndex {
                        var maxIndex = lowIndex
                        var maxValue = spectrum[lowIndex]
                        if highIndex > lowIndex {
                            for i in lowIndex...highIndex where spectrum[i] > maxValue {
                                maxValue = spectrum[i]
                                maxIndex = i
                            }
                        }
                        let hrFrequency = Double(maxIndex) * freqResolution
                        freqHeartRate = hrFrequency * 60.0
                    }
                }
            }

            let heartRate = timeDomainHR > 0 ? timeDomainHR : freqHeartRate

            let peaksWithoutOutliers: [Int]
            if outlierPeaks.isEmpty {
                peaksWithoutOutliers = peaks
            } else {
                let outlierSet = Set(outlierPeaks)
                peaksWithoutOutliers = peaks.filter { !outlierSet.contains($0) }
            }

            var logisticFeaturesWithOutliers: [String: Double]? = nil
            var logisticFeaturesWithoutOutliers: [String: Double]? = nil
            var afProbabilityWithOutliers: Double? = nil
            var afProbabilityWithoutOutliers: Double? = nil

            if let features = self.logisticFeatures(peaks: peaks, timestamps: tWindow, chromSignal: chromSignal) {
                logisticFeaturesWithOutliers = features
                afProbabilityWithOutliers = afDetector.probability(for: features)
            }

            if peaksWithoutOutliers == peaks {
                logisticFeaturesWithoutOutliers = logisticFeaturesWithOutliers
                afProbabilityWithoutOutliers = afProbabilityWithOutliers
            } else if let features = self.logisticFeatures(peaks: peaksWithoutOutliers, timestamps: tWindow, chromSignal: chromSignal) {
                logisticFeaturesWithoutOutliers = features
                afProbabilityWithoutOutliers = afDetector.probability(for: features)
            }

            let vitals = VitalSigns(heartRate: heartRate, hrvCorrected: hrvCorrected, hrvMeasured: hrvMeasured)
            let rawVitals = VitalSigns(heartRate: rawHR, hrvCorrected: rawHrvCorrected, hrvMeasured: rawHrvMeasured)
            dataQueue.sync {
                lastVitals = vitals
                lastAnalysis = SignalAnalysis(rawChromSignal: chromSignal,
                                             filteredChromSignal: filtered,
                                             timestamps: tWindow,
                                             peaks: peaks,
                                             outlierPeaks: outlierPeaks,
                                             vitals: vitals,
                                             rawVitals: rawVitals,
                                             outliersRemoved: removed > 0,
                                             frameRate: sampleRate,
                                             afProbabilityWithOutliers: afProbabilityWithOutliers,
                                             afProbabilityWithoutOutliers: afProbabilityWithoutOutliers,
                                             afFeaturesWithOutliers: logisticFeaturesWithOutliers,
                                             afFeaturesWithoutOutliers: logisticFeaturesWithoutOutliers)
            }
            return vitals
        }
    }


    /// Build the feature dictionary supplied to the logistic AF detector.
    /// - Parameters:
    ///   - peaks: Indices of detected peaks within the filtered signal window.
    ///   - timestamps: Capture timestamps for each sample in the window.
    ///   - chromSignal: Raw CHROM projection values for the window.
    /// - Returns: The feature dictionary or `nil` when there is insufficient data.
    func logisticFeatures(peaks: [Int], timestamps: [Double], chromSignal: [Double]) -> [String: Double]? {
        guard peaks.count >= 3,
              let firstTimestamp = timestamps.first,
              let lastTimestamp = timestamps.last,
              lastTimestamp > firstTimestamp else { return nil }

        var intervals: [Double] = []
        intervals.reserveCapacity(peaks.count - 1)
        for i in 1..<peaks.count {
            let currentIndex = peaks[i]
            let previousIndex = peaks[i - 1]
            guard currentIndex < timestamps.count, previousIndex < timestamps.count else { return nil }
            let dt = timestamps[currentIndex] - timestamps[previousIndex]
            intervals.append(dt)
        }

        let rrMin = 0.3
        let rrMax = 2.0
        let rrIntervals = intervals.filter { $0 >= rrMin && $0 <= rrMax }
        guard rrIntervals.count >= 2 else { return nil }

        let successiveDiffs = (1..<rrIntervals.count).map { rrIntervals[$0] - rrIntervals[$0 - 1] }
        let rrMean = mean(rrIntervals)
        let rrMedian = Self.median(rrIntervals)
        let rrStd = sampleStandardDeviation(rrIntervals)
        let rmssd = successiveDiffs.isEmpty ? 0 : sqrt(successiveDiffs.reduce(0) { $0 + $1 * $1 } / Double(successiveDiffs.count))
        let pnn50 = successiveDiffs.isEmpty ? 0 : Double(successiveDiffs.filter { abs($0) > 0.05 }.count) / Double(successiveDiffs.count)
        let heartRates = rrIntervals.map { 60.0 / $0 }
        let hrMean = mean(heartRates)
        let hrStd = sampleStandardDeviation(heartRates)
        let duration = lastTimestamp - firstTimestamp
        let beatsPerSecond = duration > 0 ? Double(peaks.count) / duration : 0
        let ppgMean = mean(chromSignal)
        let ppgStd = sampleStandardDeviation(chromSignal)

        return [
            "mean_rr": rrMean,
            "median_rr": rrMedian,
            "std_rr": rrStd,
            "rmssd": rmssd,
            "pnn50": pnn50,
            "hr_mean": hrMean,
            "hr_std": hrStd,
            "num_beats": Double(peaks.count),
            "beats_per_second": beatsPerSecond,
            "ppg_mean": ppgMean,
            "ppg_std": ppgStd,
        ]
    }


    /// Merge spuriously short inter-beat intervals with the following beat when
    /// their combined duration matches the expected cadence, correcting double
    /// peak detections.
    /// - Parameter ibis: Raw inter-beat intervals in seconds.
    /// - Returns: Tuple of cleaned intervals and the indices of removed peaks.
    static func removeDoubleBeatOutliers(_ ibis: [Double]) -> ([Double], [Int]) {
        guard !ibis.isEmpty else { return (ibis, []) }
        let med = median(ibis)
        let shortThreshold = 0.6 * med
        let combinedLower = 0.8 * med
        let combinedUpper = 1.2 * med
        var cleaned: [Double] = []
        var removed: [Int] = []
        var i = 0
        while i < ibis.count {
            let current = ibis[i]
            if current < shortThreshold && i + 1 < ibis.count {
                let next = ibis[i + 1]
                let sum = current + next
                if sum > combinedLower && sum < combinedUpper {
                    cleaned.append(sum)
                    removed.append(i + 1)
                    i += 2
                    continue
                }
            }
            cleaned.append(current)
            i += 1
        }
        return (cleaned, removed)
    }

    /// Median of the supplied values.
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func normalize(_ values: [Double]) -> [Double] {
        let m = mean(values)
        guard m != 0 else { return values }
        return values.map { ($0 - m) / m }
    }

    private func std(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count)
        return sqrt(variance)
    }

    /// Root mean square of successive differences for inter-beat intervals, in milliseconds.
    private func rmssd(_ intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        var sumSquares = 0.0
        for i in 1..<intervals.count {
            let diff = intervals[i] - intervals[i - 1]
            sumSquares += diff * diff
        }
        let meanSquare = sumSquares / Double(intervals.count - 1)
        return sqrt(meanSquare) * 1000.0
    }

    private func sampleStandardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    /// Append a sample to the waveform buffer, apply smoothing, and publish
    /// the latest window.
    private func publishWaveformSample(_ sample: Double) {
        dataQueue.sync {
            smoothingBuffer.append(sample)
            if smoothingBuffer.count > 5 {
                smoothingBuffer.removeFirst()
            }
            let smoothed = smoothingBuffer.reduce(0, +) / Double(smoothingBuffer.count)
            if waveform.samples.count < waveformWindow {
                waveform.samples.append(smoothed)
                waveform.index = waveform.samples.count % waveformWindow
            } else {
                waveform.samples[waveform.index] = smoothed
                waveform.index = (waveform.index + 1) % waveformWindow
            }
            waveformSubject.send(waveform)
        }
    }

    /// Compute a new band-passed sample from the most recent color values.
    private func updateWaveform() {
        let snapshot = dataQueue.sync { (rValues, gValues, bValues, timestamps) }
        guard snapshot.0.count >= waveformWindow else { return }
        let rWindow = Array(snapshot.0.suffix(waveformWindow))
        let gWindow = Array(snapshot.1.suffix(waveformWindow))
        let bWindow = Array(snapshot.2.suffix(waveformWindow))
        let tWindow = Array(snapshot.3.suffix(waveformWindow))
        let duration = tWindow.last! - tWindow.first!
        let sampleRate = duration > 0 ? Double(waveformWindow - 1) / duration : 30.0
        let nr = normalize(rWindow)
        let ng = normalize(gWindow)
        let nb = normalize(bWindow)
        var x = [Double](repeating: 0, count: waveformWindow)
        var y = [Double](repeating: 0, count: waveformWindow)
        for i in 0..<waveformWindow {
            x[i] = 3 * nr[i] - 2 * ng[i]
            y[i] = 1.5 * nr[i] + ng[i] - 1.5 * nb[i]
        }
        let alpha = std(x) / std(y)
        let s = zip(x, y).map { $0 - alpha * $1 }
        let filtered = Filtering.bandpass(s, sampleRate: sampleRate)
        guard let last = filtered.last else { return }
        publishWaveformSample(last)
    }

}
#endif

