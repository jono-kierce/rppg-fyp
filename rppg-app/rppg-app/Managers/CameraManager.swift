#if canImport(AVFoundation) && canImport(Combine)
import AVFoundation
import Combine

/// Handles camera configuration and publishes frames.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let framePublisher = PassthroughSubject<(CVPixelBuffer, Double), Never>()
    /// Underlying capture session used to drive camera input.
    let session = AVCaptureSession()

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var device: AVCaptureDevice?
    private var shouldFreezeSettings = false

    /// Configure and start the capture session.
    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            let useMaxFrameRate = UserDefaults.standard.bool(forKey: "useMaxFrameRate")
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .front),
                  let input = try? AVCaptureDeviceInput(device: frontCamera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.device = frontCamera

            do {
                try frontCamera.lockForConfiguration()
                if useMaxFrameRate {
                    if let maxFormat = frontCamera.formats
                        .compactMap({ format -> (AVCaptureDevice.Format, AVFrameRateRange)? in
                            guard let range = format.videoSupportedFrameRateRanges.first else { return nil }
                            return (format, range)
                        })
                        .max(by: { $0.1.maxFrameRate < $1.1.maxFrameRate }) {
                        frontCamera.activeFormat = maxFormat.0
                        let range = maxFormat.1
                        frontCamera.activeVideoMinFrameDuration = range.minFrameDuration
                        frontCamera.activeVideoMaxFrameDuration = range.minFrameDuration
                    }
                }
                if frontCamera.isExposureModeSupported(.continuousAutoExposure) {
                    frontCamera.exposureMode = .continuousAutoExposure
                }
                if frontCamera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    frontCamera.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                frontCamera.unlockForConfiguration()
            } catch {
                print("Failed to configure device: \(error)")
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = !useMaxFrameRate
            let queue = DispatchQueue(label: "CameraOutputQueue")
            output.setSampleBufferDelegate(self, queue: queue)

            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }

            if let connection = output.connection(with: .video) {
                connection.videoRotationAngle = 90
                connection.isVideoMirrored = true
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    /// Call when ROI/face is detected to freeze auto settings.
    func freezeAutoExposureAndWhiteBalance() {
        shouldFreezeSettings = true
    }

    private func lockCurrentSettings() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device configuration: \(error)")
        }
    }

    /// Capture output delegate method.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        framePublisher.send((pixelBuffer, CMTimeGetSeconds(presentationTime)))

        if shouldFreezeSettings {
            lockCurrentSettings()
            shouldFreezeSettings = false
        }

        guard UserDefaults.standard.bool(forKey: "saveRawClip") else { return }

        if assetWriter == nil {
            startWriter(with: pixelBuffer)
        }

        if assetWriter != nil,
           let input = assetWriterInput,
           let adaptor = pixelBufferAdaptor,
           input.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }
    }

    private func startWriter(with pixelBuffer: CVPixelBuffer) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rawClip.mov")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ])

            if writer.canAdd(input) {
                writer.add(input)
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String:
                            NSNumber(value: kCVPixelFormatType_32BGRA)
                    ])
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)

                assetWriter = writer
                assetWriterInput = input
                pixelBufferAdaptor = adaptor
            }
        } catch {
            print("Failed to set up AVAssetWriter: \(error)")
        }
    }
}
#endif
