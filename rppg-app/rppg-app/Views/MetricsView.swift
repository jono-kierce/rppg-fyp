#if canImport(SwiftUI)
import SwiftUI

/// Shows basic vital sign metrics in card-like tiles.
struct MetricsView: View {
    let vitals: VitalSigns?
    let afProbability: Double?
    let isAFProbabilityAvailable: Bool
    @AppStorage("hrvCorrectionEnabled") private var hrvCorrectionEnabled: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            MetricTile(
                symbol: "heart.fill",
                title: "Heart Rate",
                value: formattedHeartRate,
                unit: "bpm",
                tint: .accentColor
            )
            MetricTile(
                symbol: "waveform.path.ecg",
                title: "HRV",
                value: formattedHRV,
                unit: "ms",
                tint: .accentColor
            )
            if isAFProbabilityAvailable {
                let assessment = AFRiskAssessment(probability: afProbability)
                MetricTile(
                    symbol: assessment.iconName,
                    title: "AF Risk",
                    value: assessment.percentageText ?? "--",
                    unit: assessment.shortLabel,
                    tint: assessment.tint
                )
            }
        }
    }

    private var formattedHeartRate: String {
        if let hr = vitals?.heartRate { return String(format: "%.0f", hr) }
        else { return "--" }
    }

    private var formattedHRV: String {
        if let hrv = displayedHRV { return String(format: "%.0f", hrv) }
        else { return "--" }
    }

    private var displayedHRV: Double? {
        guard let vitals else { return nil }
        return hrvCorrectionEnabled ? vitals.hrvCorrected : vitals.hrvMeasured
    }
}

private struct MetricTile: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(tint)
            Text("\(value) \(unit)")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("CardBackground"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(0.08))
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

#Preview {
    MetricsView(
        vitals: .init(heartRate: 72, hrvCorrected: 52, hrvMeasured: 48),
        afProbability: 0.82,
        isAFProbabilityAvailable: true
    )
        .padding()
        .background(Color("Background"))
}

#Preview("Unavailable AF") {
    MetricsView(
        vitals: .init(heartRate: 72, hrvCorrected: 52, hrvMeasured: 48),
        afProbability: nil,
        isAFProbabilityAvailable: true
    )
        .padding()
        .background(Color("Background"))
}
#endif
