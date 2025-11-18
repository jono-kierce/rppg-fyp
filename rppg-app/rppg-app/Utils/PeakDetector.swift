#if canImport(Foundation)
import Foundation

/// Detects prominent peaks in a numeric signal.
/// The algorithm computes an adaptive threshold over a one-second sliding
/// window, collects local maxima above that threshold, and then suppresses
/// closely spaced peaks to avoid double counting, such as secondary T-waves.
struct PeakDetector {
    /// Detect peaks in the provided signal.
    /// - Parameters:
    ///   - signal: Input samples (typically band-pass filtered).
    ///   - sampleRate: Sampling rate of the signal in Hz.
    /// - Returns: Indices of detected peaks within ``signal``.
    ///
    /// The threshold adapts to local statistics over a one-second window.
    static func detect(in signal: [Double], sampleRate: Double) -> [Int] {
        guard signal.count >= 3 else { return [] }

        let n = signal.count
        let window = max(Int(sampleRate), 1)
        let refractory = Int(0.3 * sampleRate)
        let minRR = Int(0.4 * sampleRate)

        var prefixSum = [Double](repeating: 0, count: n + 1)
        var prefixSq = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            prefixSum[i + 1] = prefixSum[i] + signal[i]
            prefixSq[i + 1] = prefixSq[i] + signal[i] * signal[i]
        }

        var candidates: [(Int, Double)] = []
        for i in 1..<(n - 1) {
            let start = max(0, i - window + 1)
            let count = i - start + 1
            let sum = prefixSum[i + 1] - prefixSum[start]
            let sumSq = prefixSq[i + 1] - prefixSq[start]
            let mean = sum / Double(count)
            let variance = max(sumSq / Double(count) - mean * mean, 0)
            let std = sqrt(variance)
            let threshold = mean + 0.1 * std
            if signal[i] > threshold && signal[i] > signal[i - 1] && signal[i] >= signal[i + 1] {
                candidates.append((i, signal[i]))
            }
        }

        candidates.sort { $0.1 > $1.1 }

        var peaks: [(Int, Double)] = []
        for (idx, amp) in candidates {
            if peaks.allSatisfy({ abs(idx - $0.0) >= refractory }) {
                peaks.append((idx, amp))
            }
        }

        peaks.sort { $0.0 < $1.0 }

        var filtered: [(Int, Double)] = []
        for (idx, amp) in peaks {
            if let last = filtered.last, idx - last.0 <= minRR {
                if amp > last.1 {
                    filtered[filtered.count - 1] = (idx, amp)
                }
            } else {
                filtered.append((idx, amp))
            }
        }

        return filtered.map { $0.0 }
    }

}
#endif

