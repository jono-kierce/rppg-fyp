#if canImport(SwiftUI)
import SwiftUI

/// Displays the waveform, detected peaks and summary metrics after a measurement session.
@MainActor
struct MeasurementResultView: View {
    let result: SignalAnalysis
    @State private var removeOutliers: Bool = true
    @AppStorage("hrvCorrectionEnabled") private var hrvCorrectionEnabled: Bool = true

    private var displayedVitals: VitalSigns {
        removeOutliers ? result.vitals : result.rawVitals
    }

    private var displayedHRV: Double {
        let vitals = displayedVitals
        return hrvCorrectionEnabled ? vitals.hrvCorrected : vitals.hrvMeasured
    }

    private var displayedAFProbability: Double? {
        if removeOutliers {
            return result.afProbabilityWithoutOutliers ?? result.afProbabilityWithOutliers
        } else {
            return result.afProbabilityWithOutliers ?? result.afProbabilityWithoutOutliers
        }
    }

    private var afAssessment: AFRiskAssessment {
        AFRiskAssessment(probability: displayedAFProbability)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if result.outliersRemoved {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected and removed outlier beats.")
                            .font(.subheadline)
                        Toggle("Remove outliers", isOn: $removeOutliers)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(8)
                }
                MetricsRow(vitals: displayedVitals, hrv: displayedHRV)

                VStack(spacing: 8) {
                    Label {
                        Text("Frame Rate \(String(format: "%.1f", result.frameRate)) fps")
                    } icon: {
                        Image(systemName: "gauge.medium")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    WaveformView(
                        signal: result.filteredChromSignal,
                        peaks: removeOutliers ? result.peaks.filter { !result.outlierPeaks.contains($0) } : result.peaks,
                        outlierPeaks: removeOutliers ? result.outlierPeaks : [],
                        frameRate: result.frameRate)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }

                AFProbabilitySummaryView(assessment: afAssessment)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }
}

private struct MetricsRow: View {
    let vitals: VitalSigns
    let hrv: Double

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                MetricCard(
                    title: "Heart Rate",
                    value: "\(Int(vitals.heartRate)) bpm",
                    iconName: "heart.fill",
                    tint: .pink
                )

                MetricCard(
                    title: "HRV",
                    value: "\(Int(hrv)) ms",
                    iconName: "waveform.path.ecg",
                    tint: .teal
                )
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                MetricCard(
                    title: "Heart Rate",
                    value: "\(Int(vitals.heartRate)) bpm",
                    iconName: "heart.fill",
                    tint: .pink
                )

                MetricCard(
                    title: "HRV",
                    value: "\(Int(hrv)) ms",
                    iconName: "waveform.path.ecg",
                    tint: .teal
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let iconName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(tint.opacity(0.8), tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private var cardBackground: Color {
#if canImport(UIKit)
        Color(.secondarySystemBackground)
#elseif canImport(AppKit)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color.gray.opacity(0.12)
#endif
    }
}

private struct AFProbabilitySummaryView: View {
    let assessment: AFRiskAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(assessment.headline)
                        .font(.headline)
                } icon: {
                    Image(systemName: assessment.iconName)
                        .foregroundColor(assessment.tint)
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                if let percentage = assessment.percentageText {
                    Text(percentage)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(assessment.tint)
                }
            }
            Text(assessment.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(assessment.background)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(assessment.headline). \(assessment.detail)")
        )
    }
}

/// Interactive waveform with pinch zoom, drag panning and grid/axis overlays.
@MainActor
struct WaveformView: View {
    let signal: [Double]
    /// Indices of peaks to draw in red.
    let peaks: [Int]
    /// Indices of outlier peaks to draw in orange.
    let outlierPeaks: [Int]
    /// Sampling frame rate in frames per second.
    let frameRate: Double

    @State private var zoom: CGFloat = 1
    @State private var offset: CGFloat = 0
    @State private var lastZoom: CGFloat = 1
    @State private var lastOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let minVal = signal.min() ?? 0
            let maxVal = signal.max() ?? 1
            let stepX = width / CGFloat(max(signal.count - 1, 1)) * zoom
            let startIndex = max(0, Int(offset / stepX))
            let endIndex = min(signal.count - 1, Int((offset + width) / stepX))
            let startTime = Double(startIndex) / frameRate
            let endTime = Double(endIndex) / frameRate

            ZStack {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawWaveform(in: &context, width: width, height: height,
                                 minVal: minVal, maxVal: maxVal,
                                 start: startIndex, end: endIndex)
                    drawPeaks(in: &context, width: width, height: height,
                              minVal: minVal, maxVal: maxVal,
                              start: startIndex, end: endIndex)
                    drawOutliers(in: &context, width: width, height: height,
                                 minVal: minVal, maxVal: maxVal,
                                 start: startIndex, end: endIndex)
                }

                // Time axis labels
                HStack {
                    Text(String(format: "%.2f", startTime))
                    Spacer()
                    Text(String(format: "%.2f", endTime))
                }
                .font(.caption2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 4)
            }
            .gesture(gesture(width: width))
        }
    }

    /// Draw vertical/horizontal grid lines and axes.
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let divisions = 4
        for i in 0...divisions {
            var hLine = Path()
            let y = size.height * CGFloat(i) / CGFloat(divisions)
            hLine.move(to: CGPoint(x: 0, y: y))
            hLine.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hLine, with: .color(.gray.opacity(0.2)), lineWidth: 1)
        }
        for i in 0...divisions {
            var vLine = Path()
            let x = size.width * CGFloat(i) / CGFloat(divisions)
            vLine.move(to: CGPoint(x: x, y: 0))
            vLine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vLine, with: .color(.gray.opacity(0.2)), lineWidth: 1)
        }

        var axes = Path()
        axes.move(to: .zero)
        axes.addLine(to: CGPoint(x: 0, y: size.height))
        axes.move(to: CGPoint(x: 0, y: size.height))
        axes.addLine(to: CGPoint(x: size.width, y: size.height))
        context.stroke(axes, with: .color(.gray), lineWidth: 1)
    }

    /// Draw the waveform for the visible range.
    private func drawWaveform(
        in context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        minVal: Double,
        maxVal: Double,
        start: Int,
        end: Int
    ) {
        guard maxVal - minVal > 0 else { return }
        let stepX = width / CGFloat(max(signal.count - 1, 1)) * zoom
        var path = Path()
        if start <= end {
            for i in start...end {
                let x = CGFloat(i) * stepX - offset
                let norm = (signal[i] - minVal) / (maxVal - minVal)
                let y = height * (1 - CGFloat(norm))
                if i == start { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.blue), lineWidth: 2)
        }
    }

    /// Draw peak markers for the visible range.
    private func drawPeaks(
        in context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        minVal: Double,
        maxVal: Double,
        start: Int,
        end: Int
    ) {
        guard maxVal - minVal > 0 else { return }
        let stepX = width / CGFloat(max(signal.count - 1, 1)) * zoom
        for idx in peaks where idx >= start && idx <= end {
            let x = CGFloat(idx) * stepX - offset
            let value = signal[idx]
            let norm = (value - minVal) / (maxVal - minVal)
            let y = height * (1 - CGFloat(norm))
            let circle = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            context.fill(circle, with: .color(.red))
        }
    }

    /// Draw outlier peak markers for the visible range.
    private func drawOutliers(
        in context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        minVal: Double,
        maxVal: Double,
        start: Int,
        end: Int
    ) {
        guard maxVal - minVal > 0 else { return }
        let stepX = width / CGFloat(max(signal.count - 1, 1)) * zoom
        for idx in outlierPeaks where idx >= start && idx <= end {
            let x = CGFloat(idx) * stepX - offset
            let value = signal[idx]
            let norm = (value - minVal) / (maxVal - minVal)
            let y = height * (1 - CGFloat(norm))
            let rect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(.orange))
        }
    }

    /// Combined pinch-to-zoom and drag-to-pan gesture.
    private func gesture(width: CGFloat) -> some Gesture {
        let magnify = MagnificationGesture()
            .onChanged { value in
                zoom = min(max(lastZoom * value, 1), 10)
                let maxOffset = width * (zoom - 1)
                offset = min(max(offset, 0), maxOffset)
            }
            .onEnded { _ in
                lastZoom = zoom
            }

        let drag = DragGesture()
            .onChanged { value in
                let maxOffset = width * (zoom - 1)
                let newOffset = lastOffset - value.translation.width
                offset = min(max(0, newOffset), maxOffset)
            }
            .onEnded { _ in
                lastOffset = offset
            }

        return magnify.simultaneously(with: drag)
    }
}

#Preview {
    MeasurementResultView(
        result: SignalAnalysis(
            rawChromSignal: [0, 0.5, 0.1, -0.2, 0.0],
            filteredChromSignal: [0, 1, 0, 1, 0],
            timestamps: [0, 0.1, 0.2, 0.3, 0.4],
            peaks: [1, 3],
            outlierPeaks: [],
            vitals: VitalSigns(heartRate: 72, hrvCorrected: 52, hrvMeasured: 48),
            rawVitals: VitalSigns(heartRate: 72, hrvCorrected: 50, hrvMeasured: 50),
            outliersRemoved: false,
            frameRate: 30,
            afProbabilityWithOutliers: 0.82,
            afProbabilityWithoutOutliers: 0.78,
            afFeaturesWithOutliers: nil,
            afFeaturesWithoutOutliers: nil
        )
    )
}

#Preview("Unavailable AF") {
    MeasurementResultView(
        result: SignalAnalysis(
            rawChromSignal: [0, 0.5, 0.1, -0.2, 0.0],
            filteredChromSignal: [0, 1, 0, 1, 0],
            timestamps: [0, 0.1, 0.2, 0.3, 0.4],
            peaks: [1, 3],
            outlierPeaks: [],
            vitals: VitalSigns(heartRate: 72, hrvCorrected: 52, hrvMeasured: 48),
            rawVitals: VitalSigns(heartRate: 72, hrvCorrected: 50, hrvMeasured: 50),
            outliersRemoved: true,
            frameRate: 30,
            afProbabilityWithOutliers: nil,
            afProbabilityWithoutOutliers: nil,
            afFeaturesWithOutliers: nil,
            afFeaturesWithoutOutliers: nil
        )
    )
}
#endif
