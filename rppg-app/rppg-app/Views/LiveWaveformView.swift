#if canImport(SwiftUI)
import SwiftUI

/// Lightweight ring-buffer waveform for the live heart-rate signal.
struct LiveWaveformView: View {
    let waveform: Waveform

    var body: some View {
        Canvas { context, size in
            let samples = waveform.samples
            guard samples.count >= 2,
                  let minVal = samples.min(),
                  let maxVal = samples.max(),
                  maxVal - minVal > 0 else { return }
            let scaleY = size.height / CGFloat(maxVal - minVal)

            if waveform.index >= samples.count {
                let stepX = size.width / CGFloat(samples.count - 1)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height - (CGFloat(samples[0] - minVal) * scaleY)))
                for i in 1..<samples.count {
                    let x = CGFloat(i) * stepX
                    let y = size.height - (CGFloat(samples[i] - minVal) * scaleY)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(Color.red.opacity(0.6)), lineWidth: 2)
            } else {
                let stepX = size.width / CGFloat(samples.count)
                let gap = 2
                let start = (waveform.index + gap) % samples.count

                var path = Path()
                var i = start
                var first = true
                repeat {
                    let x = CGFloat(i) * stepX
                    let y = size.height - (CGFloat(samples[i] - minVal) * scaleY)
                    if first {
                        path.move(to: CGPoint(x: x, y: y))
                        first = false
                    } else {
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    i = (i + 1) % samples.count
                } while i != waveform.index
                context.stroke(path, with: .color(Color.red.opacity(0.6)), lineWidth: 2)
            }
        }
        .frame(height: 60)
    }
}

#Preview {
    let samples = (0..<210).map { sin(Double($0) / 10) }
    LiveWaveformView(waveform: Waveform(samples: samples, index: 0))
        .padding()
        .background(Color("Background"))
}
#endif
