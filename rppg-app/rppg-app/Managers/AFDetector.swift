import Foundation

/// Protocol for optional remote atrial fibrillation inference services.
protocol AFRemoteClassifying {
    /// Request a remote probability estimate using the provided feature dictionary.
    func probability(for features: [String: Double]) async throws -> Double
}

/// Handles AF detection using a bundled logistic model with optional remote fallback.
final class AFDetector {
    private let remote: AFRemoteClassifying?
    private let bundle: Bundle
    private let modelResourceName: String

    #if SWIFT_PACKAGE
    static let resourceBundle = Bundle.module
    #else
    static let resourceBundle = Bundle.main
    #endif

    private lazy var localModel: AFLogisticModel? = {
        guard let url = bundle.url(forResource: modelResourceName, withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(AFLogisticModel.self, from: data)
        } catch {
            return nil
        }
    }()

    /// Initialize the detector and optionally provide a remote classifier.
    /// - Parameters:
    ///   - remote: Optional remote service used when the local model is unavailable.
    ///   - bundle: Bundle containing the logistic model artifact. Defaults to the package's
    ///     resource bundle when built via Swift Package Manager and `.main` otherwise.
    ///   - modelResourceName: Name of the bundled JSON file (without extension).
    init(remote: AFRemoteClassifying? = nil, bundle: Bundle = AFDetector.resourceBundle, modelResourceName: String = "af_logistic_model") {
        self.remote = remote
        self.bundle = bundle
        self.modelResourceName = modelResourceName
    }

    /// Compute the local probability estimate for the supplied features.
    /// - Parameter features: Dictionary of feature values keyed by their name.
    /// - Returns: The local probability or `nil` if the bundled model is missing or incomplete.
    func probability(for features: [String: Double]) -> Double? {
        localModel?.probability(for: features)
    }

    /// Compute the probability using the local model or fall back to the remote service.
    /// - Parameter features: Dictionary of feature values keyed by their name.
    /// - Returns: A probability estimate, preferring the local model but forwarding remote results when needed.
    func probabilityWithRemoteFallback(for features: [String: Double]) async throws -> Double {
        if let local = probability(for: features) {
            return local
        }

        guard let remote else {
            throw AFError.modelUnavailable
        }

        return try await remote.probability(for: features)
    }
}

/// AF detection related errors.
enum AFError: Error {
    case modelUnavailable
}
