#if canImport(Vision)
import Foundation
import Vision
import CoreMedia
import CoreGraphics

/// Evaluates motion stability of the user's forehead region.
final class MotionEvaluator {
    /// Smoothed rectangle for drawing the ROI.
    private var smoothedROI: CGRect?
    /// Last raw face box used for motion comparison.
    private var lastFaceObservation: CGRect?

    /// Analyze the current frame for motion and provide the detected face box.
    /// - Parameter pixelBuffer: The camera frame to analyze.
    func evaluate(_ pixelBuffer: CVPixelBuffer) -> MotionResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let detect = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([detect])
            guard let face = (detect.results as? [VNFaceObservation])?.first else {
                smoothedROI = nil
                lastFaceObservation = nil
                return MotionResult(isStable: false, faceBoundingBox: nil, roiBoundingBox: nil)
            }

            // Use the face bounds but trim a bit horizontally for nicer visuals.
            let bb = face.boundingBox.insetBy(dx: face.boundingBox.width * 0.1, dy: 0)

            // Approximate a forehead ROI near the top of the face box.
            let rawForehead = CGRect(
                x: bb.origin.x + bb.width * 0.3,
                y: bb.origin.y + bb.height * 0.8,
                width: bb.width * 0.4,
                height: bb.height * 0.15
            )

            // Light exponential smoothing to reduce jitter of the ROI.
            let smoothing: CGFloat = 0.2
            let forehead: CGRect
            if let last = smoothedROI {
                forehead = interpolate(from: last, to: rawForehead, factor: smoothing)
            } else {
                forehead = rawForehead
            }

            var stable = false
            if let last = lastFaceObservation {
                let movement = distance(from: last, to: bb)
                // Threshold tuned empirically; smaller is more sensitive.
                stable = movement < 0.02
            }
            smoothedROI = forehead
            lastFaceObservation = bb

            return MotionResult(isStable: stable, faceBoundingBox: bb, roiBoundingBox: forehead)
        } catch {
            smoothedROI = nil
            lastFaceObservation = nil
            // Treat Vision failures as instability so the UI can react.
            return MotionResult(isStable: false, faceBoundingBox: nil, roiBoundingBox: nil)
        }
    }

    private func distance(from: CGRect, to: CGRect) -> CGFloat {
        let dx = from.midX - to.midX
        let dy = from.midY - to.midY
        return sqrt(dx * dx + dy * dy)
    }

    private func interpolate(from: CGRect, to: CGRect, factor: CGFloat) -> CGRect {
        let inv = 1 - factor
        return CGRect(
            x: from.origin.x * inv + to.origin.x * factor,
            y: from.origin.y * inv + to.origin.y * factor,
            width: from.size.width * inv + to.size.width * factor,
            height: from.size.height * inv + to.size.height * factor
        )
    }
}
#endif
