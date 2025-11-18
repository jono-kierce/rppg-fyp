import Foundation

/// Represents a lightweight logistic regression model for atrial fibrillation detection.
struct AFLogisticModel: Decodable {
    /// Metadata describing a single feature used by the logistic model.
    struct Feature: Decodable {
        /// Name of the feature.
        let name: String
        /// Mean used by the StandardScaler during training.
        let scaleMean: Double
        /// Scale used by the StandardScaler during training.
        let scaleScale: Double
        /// Coefficient assigned to the feature in the logistic regression.
        let coefficient: Double

        private enum CodingKeys: String, CodingKey {
            case name
            case scaleMean = "scale_mean"
            case scaleScale = "scale_scale"
            case coefficient
        }
    }

    /// Ordered list of features required by the model.
    let features: [Feature]
    /// Intercept term added before the sigmoid activation.
    let intercept: Double

    /// Ordered feature names expected by the model.
    var featureNames: [String] { features.map { $0.name } }

    /// Compute the probability of atrial fibrillation using the provided feature values.
    ///
    /// The values are ordered to match the stored feature sequence, normalized with the
    /// associated StandardScaler statistics, and evaluated with the logistic sigmoid.
    /// - Parameter rawFeatures: Dictionary of feature values keyed by the feature name.
    /// - Returns: The probability of atrial fibrillation or `nil` if any required feature is missing.
    func probability(for rawFeatures: [String: Double]) -> Double? {
        var linear = intercept

        for feature in features {
            guard let value = rawFeatures[feature.name], feature.scaleScale != 0 else {
                return nil
            }

            let normalized = (value - feature.scaleMean) / feature.scaleScale
            linear += normalized * feature.coefficient
        }

        return 1.0 / (1.0 + exp(-linear))
    }
}
