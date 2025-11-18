#if canImport(SwiftUI) && canImport(AVFoundation)
import SwiftUI
import AVFoundation

/// Displays the camera feed using `AVCaptureVideoPreviewLayer`.
struct LivePreviewView: UIViewRepresentable {
    /// The capture session providing frames for display.
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        // Use a valid `AVLayerVideoGravity` value to size the preview layer.
        // `.resizeAspect` preserves the aspect ratio of the video while
        // fitting it within the layer's bounds (similar to "aspect fit").
        view.videoPreviewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Layer automatically adjusts to view bounds.
    }
}

/// UIView backed by `AVCaptureVideoPreviewLayer` for quick integration.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
#endif
