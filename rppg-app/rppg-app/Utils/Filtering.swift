import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Common signal-processing utilities.
enum Filtering {
    /// Apply a bandpass filter to the signal.
    /// If the Accelerate framework is available, an FFT-based implementation
    /// is used. Otherwise, a simple first-order high-pass and low-pass filter
    /// combination is applied.
    /// - Parameters:
    ///   - signal: Input samples.
    ///   - sampleRate: Sampling rate of the signal in Hz.
    ///   - lowCut: Low cut-off frequency in Hz.
    ///   - highCut: High cut-off frequency in Hz.
    /// - Returns: Filtered signal.
    static func bandpass(
        _ signal: [Double],
        sampleRate: Double = 30.0,
        lowCut: Double = 0.7,
        highCut: Double = 4.0
    ) -> [Double] {
        let count = signal.count
        guard count > 1 else { return signal }

        #if canImport(Accelerate)
        var fftCount = count
        var paddedSignal = signal

        if (fftCount & (fftCount - 1)) != 0 {
            var nextPowerOfTwo = 1
            while nextPowerOfTwo < fftCount {
                nextPowerOfTwo <<= 1
            }
            paddedSignal.append(contentsOf: repeatElement(0.0, count: nextPowerOfTwo - fftCount))
            fftCount = nextPowerOfTwo
        }

        let log2n = vDSP_Length((Int.bitWidth - 1) - fftCount.leadingZeroBitCount)

        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
            return firstOrderBandpass(
                signal,
                sampleRate: sampleRate,
                lowCut: lowCut,
                highCut: highCut
            )
        }

        var real = paddedSignal
        var imag = [Double](repeating: 0.0, count: fftCount)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPDoubleSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                // Forward FFT.
                vDSP_fft_zipD(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // Zero out frequencies outside the passband.
                let resolution = sampleRate / Double(fftCount)
                let half = fftCount / 2
                for i in 0..<fftCount {
                    let index = i <= half ? i : i - fftCount
                    let freq = abs(Double(index)) * resolution
                    if freq < lowCut || freq > highCut {
                        split.realp[i] = 0
                        split.imagp[i] = 0
                    }
                }

                // Inverse FFT.
                vDSP_fft_zipD(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                var scale = 1.0 / Double(fftCount)
                vDSP_vsmulD(
                    split.realp,
                    1,
                    &scale,
                    realPtr.baseAddress!,
                    1,
                    vDSP_Length(fftCount)
                )
            }
        }

        vDSP_destroy_fftsetupD(setup)
        if fftCount == count {
            return real
        } else {
            return Array(real[0..<count])
        }
        #else
        return firstOrderBandpass(
            signal,
            sampleRate: sampleRate,
            lowCut: lowCut,
            highCut: highCut
        )
        #endif
    }

    /// Compute the FFT of the signal, returning a normalized magnitude
    /// spectrum for the positive frequencies. The signal length must be a
    /// power of two.
    static func fft(_ signal: [Double]) -> [Double] {
        let count = signal.count
        guard (count & (count - 1)) == 0 else { return [] }

        #if canImport(Accelerate)
        let log2n = vDSP_Length(log2(Double(count)))

        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }

        var real = signal
        var imag = [Double](repeating: 0.0, count: count)
        var magnitudes = [Double](repeating: 0.0, count: count)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    var split = DSPDoubleSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )

                    vDSP_fft_zipD(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabsD(
                        &split,
                        1,
                        magPtr.baseAddress!,
                        1,
                        vDSP_Length(count)
                    )
                    var scale = 1.0 / Double(count)
                    vDSP_vsmulD(
                        magPtr.baseAddress!,
                        1,
                        &scale,
                        magPtr.baseAddress!,
                        1,
                        vDSP_Length(count)
                    )
                }
            }
        }

        vDSP_destroy_fftsetupD(setup)
        return Array(magnitudes[0..<(count / 2)])
        #else
        guard count > 0 else { return [] }

        let half = count / 2
        var magnitudes = [Double](repeating: 0.0, count: half)

        for k in 0..<half {
            var real = 0.0
            var imag = 0.0
            for t in 0..<count {
                let angle = 2.0 * Double.pi * Double(k * t) / Double(count)
                real += signal[t] * cos(angle)
                imag -= signal[t] * sin(angle)
            }
            magnitudes[k] = sqrt(real * real + imag * imag) / Double(count)
        }

        return magnitudes
        #endif
    }
}

extension Filtering {
    private static func firstOrderBandpass(
        _ signal: [Double],
        sampleRate: Double,
        lowCut: Double,
        highCut: Double
    ) -> [Double] {
        let count = signal.count
        guard count > 1 else { return signal }

        let dt = 1.0 / sampleRate

        // High-pass stage
        let rcHigh = 1.0 / (2.0 * Double.pi * lowCut)
        let alphaHigh = rcHigh / (rcHigh + dt)
        var high = [Double](repeating: 0.0, count: count)
        high[0] = signal[0]
        for i in 1..<count {
            high[i] = alphaHigh * (high[i - 1] + signal[i] - signal[i - 1])
        }

        // Low-pass stage
        let rcLow = 1.0 / (2.0 * Double.pi * highCut)
        let alphaLow = dt / (rcLow + dt)
        var band = [Double](repeating: 0.0, count: count)
        band[0] = high[0]
        for i in 1..<count {
            band[i] = band[i - 1] + alphaLow * (high[i] - band[i - 1])
        }

        return band
    }
}

