#if canImport(SwiftUI)
import SwiftUI

/// Presents a textual and visual description of an atrial fibrillation probability.
struct AFRiskAssessment {
    enum State {
        case unavailable
        case low
        case moderate
        case high
    }

    let probability: Double?
    let state: State

    init(probability: Double?) {
        if let probability {
            let clamped = min(max(probability, 0), 1)
            self.probability = clamped
            if clamped >= 0.75 {
                state = .high
            } else if clamped >= 0.4 {
                state = .moderate
            } else {
                state = .low
            }
        } else {
            self.probability = nil
            state = .unavailable
        }
    }

    var percentageText: String? {
        guard let probability else { return nil }
        return NumberFormatter.afProbability.string(from: probability as NSNumber)
    }

    var headline: String {
        switch state {
        case .unavailable:
            return "AF Detection Unavailable"
        case .low:
            return "Low AF Risk"
        case .moderate:
            return "Moderate AF Risk"
        case .high:
            return "High AF Risk"
        }
    }

    var shortLabel: String {
        switch state {
        case .unavailable:
            return "Unavailable"
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        }
    }

    var detail: String {
        switch state {
        case .unavailable:
            return "We couldn't compute an atrial fibrillation probability for this recording. Make sure your face stays in frame and lighting remains steady, then try again."
        case .low:
            return "Signal irregularities were minimal and suggest a low likelihood of atrial fibrillation during this recording."
        case .moderate:
            return "Some irregularities were detected. Consider repeating the measurement or consulting a care provider if symptoms persist."
        case .high:
            return "This recording shows a high likelihood of atrial fibrillation. Contact a clinician promptly if you experience symptoms."
        }
    }

    var tint: Color {
        switch state {
        case .unavailable:
            return .secondary
        case .low:
            return .green
        case .moderate:
            return .orange
        case .high:
            return .red
        }
    }

    var background: Color {
        tint.opacity(0.12)
    }

    var iconName: String {
        switch state {
        case .unavailable:
            return "questionmark.circle"
        case .low:
            return "checkmark.heart"
        case .moderate:
            return "waveform.path.ecg"
        case .high:
            return "exclamationmark.triangle"
        }
    }
}

private extension NumberFormatter {
    static let afProbability: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}
#endif
