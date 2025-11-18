import Foundation

/// Container for vital sign metrics.
struct VitalSigns: Codable {
    /// Heart rate in beats per minute.
    var heartRate: Double
    /// RMSSD after applying timing-noise correction, in milliseconds.
    var hrvCorrected: Double
    /// Measured RMSSD prior to timing-noise correction, in milliseconds.
    var hrvMeasured: Double

    init(heartRate: Double, hrvCorrected: Double, hrvMeasured: Double) {
        self.heartRate = heartRate
        self.hrvCorrected = hrvCorrected
        self.hrvMeasured = hrvMeasured
    }

    init(heartRate: Double, hrvMeasured: Double) {
        self.init(heartRate: heartRate, hrvCorrected: hrvMeasured, hrvMeasured: hrvMeasured)
    }
}
