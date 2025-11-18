/// Circular buffer of samples and current write index for live waveform rendering.
struct Waveform {
    /// Samples in the circular buffer.
    var samples: [Double]
    /// Next index to be written, marking the gap between old and new data.
    var index: Int
}
