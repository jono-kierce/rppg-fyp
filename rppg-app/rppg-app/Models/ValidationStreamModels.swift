#if canImport(Foundation)
import Foundation

/// Describes a single color sample extracted from the camera feed.
struct ValidationSample: Codable {
    /// Frame index since the current measurement started.
    let frameIndex: Int
    /// Presentation timestamp reported by AVFoundation in seconds.
    let captureTimestamp: Double
    /// ``ProcessInfo.processInfo.systemUptime`` captured alongside the sample.
    let deviceUptime: Double
    /// Wall-clock timestamp in seconds since 1970.
    let wallClock: Double
    /// Band-passed rPPG estimate emitted by the signal processor.
    let estimatedSignal: Double
    /// Fraction of the frame covered by the ROI (0-1).
    let roiFraction: Double
    /// Indicates whether the sample was captured while a measurement was active.
    let isMeasurement: Bool
}

/// Configuration persisted in ``UserDefaults`` used for validation streaming.
struct ValidationStreamConfiguration: Equatable {
    var isEnabled: Bool
    var host: String
    var port: Int
    /// Optional label used to tag the exported measurement sessions.
    var sessionTag: String

    static func load(from defaults: UserDefaults = .standard) -> ValidationStreamConfiguration {
        let enabled = defaults.bool(forKey: Keys.enabled)
        let host = defaults.string(forKey: Keys.host) ?? ""
        let portValue = defaults.integer(forKey: Keys.port)
        let port = portValue > 0 ? portValue : 8765
        let tag = defaults.string(forKey: Keys.sessionTag) ?? ""
        return ValidationStreamConfiguration(isEnabled: enabled, host: host, port: port, sessionTag: tag)
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(host, forKey: Keys.host)
        defaults.set(port, forKey: Keys.port)
        defaults.set(sessionTag, forKey: Keys.sessionTag)
    }

    var endpointURL: URL? {
        guard !host.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "ws"
        comps.host = host
        comps.port = port
        comps.path = "/rppg"
        return comps.url
    }

    private enum Keys {
        static let enabled = "validationStream.enabled"
        static let host = "validationStream.host"
        static let port = "validationStream.port"
        static let sessionTag = "validationStream.sessionTag"
    }
}
#endif
