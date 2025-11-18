import Foundation

/// Utilities for correcting RMSSD values for fixed timing noise.
enum HRVCorrection {
    /// Standard deviation of timing jitter (σ) in milliseconds.
    static let jitterSigmaMs: Double = 60.0

    /// Apply the timing-noise de-biasing formula.
    /// - Parameter measured: Observed RMSSD in milliseconds.
    /// - Returns: sqrt(max(0, RMSSD_meas^2 - 2 * σ^2)).
    static func correctedRMSSD(measured: Double) -> Double {
        let squared = max(0, measured * measured - 2 * jitterSigmaMs * jitterSigmaMs)
        return sqrt(squared)
    }
}
