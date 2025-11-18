#if canImport(CoreGraphics)
import CoreGraphics

/// Result of analyzing motion in a frame.
struct MotionResult {
    /// Whether the region is considered stable.
    let isStable: Bool
    /// Normalized bounding box of the detected face, if any.
    let faceBoundingBox: CGRect?
    /// Normalized bounding box of the forehead ROI, if any.
    let roiBoundingBox: CGRect?
}
#endif
