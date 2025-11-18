#if canImport(Foundation)
import Foundation

/// Result of processing the full rPPG signal over a measurement session.
struct SignalAnalysis: Identifiable {
    let id = UUID()
    /// Raw CHROM projection prior to band-pass filtering.
    let rawChromSignal: [Double]
    /// Band-passed CHROM signal used for analysis and visualization.
    let filteredChromSignal: [Double]
    /// Capture timestamps for each processed sample in seconds.
    let timestamps: [Double]
    /// Detected peak locations in the processed signal.
    let peaks: [Int]
    /// Peak positions that were classified as outliers and merged.
    let outlierPeaks: [Int]
    /// Vital signs with suspected double-beat outliers removed.
    let vitals: VitalSigns
    /// Vital signs computed from the raw intervals including outliers.
    let rawVitals: VitalSigns
    /// Indicates whether any outlier beats were detected and removed.
    let outliersRemoved: Bool
    /// Average frame rate of the captured signal in frames per second.
    let frameRate: Double
    /// Probability of atrial fibrillation computed using the raw peaks, if available.
    let afProbabilityWithOutliers: Double?
    /// Probability of atrial fibrillation computed after removing detected outliers, if available.
    let afProbabilityWithoutOutliers: Double?
    /// Feature vector supplied to the logistic helper when computing ``afProbabilityWithOutliers``.
    let afFeaturesWithOutliers: [String: Double]?
    /// Feature vector supplied to the logistic helper when computing ``afProbabilityWithoutOutliers``.
    let afFeaturesWithoutOutliers: [String: Double]?

    /// Default AF probability used in summaries where no explicit outlier choice is provided.
    /// Prefers the outlier-free probability when available.
    var afProbability: Double? {
        afProbabilityWithoutOutliers ?? afProbabilityWithOutliers
    }

    /// Default AF feature vector matching ``afProbability``.
    var afFeatures: [String: Double]? {
        afFeaturesWithoutOutliers ?? afFeaturesWithOutliers
    }
}
#endif
