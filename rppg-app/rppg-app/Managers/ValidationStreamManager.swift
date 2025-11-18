#if canImport(Foundation)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

/// Coordinates validation session lifecycle events and measurement uploads.
actor ValidationStreamManager {
    enum ValidationStreamError: LocalizedError {
        case connectionUnavailable
        case failedToSend(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .connectionUnavailable:
                return "Unable to connect to the validation server."
            case let .failedToSend(underlying):
                return underlying.localizedDescription
            }
        }
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionID: String?
    private var isMeasurementActive = false
    private let encoder = JSONEncoder()
    private let isoFormatter: ISO8601DateFormatter
    private struct EncodingConversionError: Error {}
#if canImport(os)
    private let logger = Logger(subsystem: "rppg-app", category: "validation-stream")
#endif
    init() {
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Notify the host that a new measurement has started.
    func beginMeasurement(duration: Double) async throws {
        let config = ValidationStreamConfiguration.load()
        guard config.isEnabled else { return }
        guard let task = await ensureConnection(using: config) else {
            logError("Unable to notify validation host about measurement start.")
            sessionID = nil
            isMeasurementActive = false
            throw ValidationStreamError.connectionUnavailable
        }
        let tag = config.sessionTag.isEmpty ? "session" : config.sessionTag
        let identifier = "\(tag)-\(isoFormatter.string(from: Date()))"
        sessionID = identifier
        isMeasurementActive = true
        logInfo("Starting validation session \(identifier) destined for \(config.host):\(config.port)")
        let message = OutboundMessage(
            type: .session,
            sessionID: identifier,
            timestamp: Date().timeIntervalSince1970,
            duration: duration,
            event: "started",
            heartRate: nil,
            hrv: nil,
            measuredHrv: nil,
            summary: nil
        )
        do {
            try await send(message, on: task)
        } catch {
            sessionID = nil
            isMeasurementActive = false
            throw error
        }
    }

    /// Notify the host that measurement finished with an optional summary.
    func finishMeasurement(result: SignalAnalysis?) async {
        guard isMeasurementActive else { return }
        let identifier = sessionID
        isMeasurementActive = false
        sessionID = nil
        let config = ValidationStreamConfiguration.load()
        guard config.isEnabled, let identifier else { return }
        guard let task = await ensureConnection(using: config) else {
            logError("Unable to notify validation host about measurement completion for \(identifier).")
            return
        }
        logInfo("Finished validation session \(identifier).")
        let correctionEnabled = UserDefaults.standard.bool(forKey: "hrvCorrectionEnabled")
        if let result {
            let summary = OutboundMessage.MeasurementSummary(
                rawChromSignal: result.rawChromSignal,
                filteredChromSignal: result.filteredChromSignal,
                timestamps: result.timestamps,
                peaks: result.peaks,
                outlierPeaks: result.outlierPeaks,
                frameRate: result.frameRate,
                heartRate: result.vitals.heartRate,
                hrv: result.vitals.hrvCorrected,
                measuredHrv: result.vitals.hrvMeasured,
                rawHeartRate: result.rawVitals.heartRate,
                rawHrv: result.rawVitals.hrvMeasured,
                outliersRemoved: result.outliersRemoved,
                afProbability: result.afProbability
            )
            let summaryMessage = OutboundMessage(
                type: .measurementSummary,
                sessionID: identifier,
                timestamp: Date().timeIntervalSince1970,
                duration: nil,
                event: nil,
                heartRate: nil,
                hrv: nil,
                measuredHrv: nil,
                summary: summary
            )
            do {
                try await send(summaryMessage, on: task)
            } catch {
                logError("Failed to send summary for validation session \(identifier): \(error.localizedDescription)")
            }
        }
        let message = OutboundMessage(
            type: .session,
            sessionID: identifier,
            timestamp: Date().timeIntervalSince1970,
            duration: nil,
            event: "finished",
            heartRate: result?.vitals.heartRate,
            hrv: correctionEnabled ? result?.vitals.hrvCorrected : result?.vitals.hrvMeasured,
            measuredHrv: result?.vitals.hrvMeasured,
            summary: nil
        )
        do {
            try await send(message, on: task)
        } catch {
            logError("Failed to send completion event for validation session \(identifier): \(error.localizedDescription)")
        }
    }

    /// Notify the host that a measurement was cancelled or interrupted.
    func cancelMeasurement() async {
        guard isMeasurementActive else { return }
        let identifier = sessionID
        isMeasurementActive = false
        sessionID = nil
        let config = ValidationStreamConfiguration.load()
        guard config.isEnabled, let identifier else { return }
        guard let task = await ensureConnection(using: config) else {
            logError("Unable to notify validation host about cancelled measurement for \(identifier).")
            return
        }
        logInfo("Cancelled validation session \(identifier).")
        let message = OutboundMessage(
            type: .session,
            sessionID: identifier,
            timestamp: Date().timeIntervalSince1970,
            duration: nil,
            event: "cancelled",
            heartRate: nil,
            hrv: nil,
            measuredHrv: nil,
            summary: nil
        )
        do {
            try await send(message, on: task)
        } catch {
            logError("Failed to send cancellation event for validation session \(identifier): \(error.localizedDescription)")
        }
    }

    /// Close the connection manually when settings are toggled off.
    func shutdown() async {
        await closeConnection()
        sessionID = nil
        isMeasurementActive = false
    }

    private func ensureConnection(using config: ValidationStreamConfiguration) async -> URLSessionWebSocketTask? {
        if let task = webSocketTask, task.state == .running {
            return task
        }
        guard let url = config.endpointURL else { return nil }
        let request = URLRequest(url: url)
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        logInfo("Connecting to validation host at \(url.absoluteString)")
        task.resume()
        do {
            try await sendHello(using: task)
            return task
        } catch {
            logError("Validation host handshake failed: \(error.localizedDescription)")
            await closeConnection()
            return nil
        }
    }

    private func sendHello(using task: URLSessionWebSocketTask) async throws {
        let message = OutboundMessage(
            type: .hello,
            sessionID: nil,
            timestamp: Date().timeIntervalSince1970,
            duration: nil,
            event: nil,
            heartRate: nil,
            hrv: nil,
            measuredHrv: nil,
            summary: nil
        )
        try await send(message, on: task)
        logDebug("Sent hello handshake to validation host.")
    }

    private func send(_ message: OutboundMessage, on task: URLSessionWebSocketTask) async throws {
        do {
            let data = try encoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ValidationStreamError.failedToSend(underlying: EncodingConversionError())
            }
            try await task.send(URLSessionWebSocketTask.Message.string(text))
            logDebug("Sent \(message.type.rawValue) message to validation host.")
        } catch {
            logError("Failed to send \(message.type.rawValue) message: \(error.localizedDescription)")
            await closeConnection()
            if let streamError = error as? ValidationStreamError {
                throw streamError
            } else {
                throw ValidationStreamError.failedToSend(underlying: error)
            }
        }
    }

    private func closeConnection() async {
        guard let task = webSocketTask else { return }
        task.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)
        webSocketTask = nil
        logInfo("Closed validation stream connection.")
    }

    private func logInfo(_ message: String) {
#if canImport(os)
        logger.info("\(message, privacy: .public)")
#else
        print("[ValidationStream] INFO: \(message)")
#endif
    }

    private func logDebug(_ message: String) {
#if canImport(os)
        logger.debug("\(message, privacy: .public)")
#else
        print("[ValidationStream] DEBUG: \(message)")
#endif
    }

    private func logError(_ message: String) {
#if canImport(os)
        logger.error("\(message, privacy: .public)")
#else
        print("[ValidationStream] ERROR: \(message)")
#endif
    }

    private struct OutboundMessage: Codable {
        enum MessageType: String, Codable {
            case hello
            case session
            case measurementSummary = "measurement_summary"
        }

        let type: MessageType
        let sessionID: String?
        let timestamp: Double
        let duration: Double?
        let event: String?
        let heartRate: Double?
        let hrv: Double?
        let measuredHrv: Double?
        let summary: MeasurementSummary?

        struct MeasurementSummary: Codable {
            let rawChromSignal: [Double]
            let filteredChromSignal: [Double]
            let timestamps: [Double]
            let peaks: [Int]
            let outlierPeaks: [Int]
            let frameRate: Double
            let heartRate: Double?
            let hrv: Double?
            let measuredHrv: Double?
            let rawHeartRate: Double?
            let rawHrv: Double?
            let outliersRemoved: Bool
            let afProbability: Double?
        }
    }
}
#endif
