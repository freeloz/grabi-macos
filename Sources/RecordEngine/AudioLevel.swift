import Foundation
import AVFoundation
import Accelerate

/// RMS level 0–1 of a PCM buffer, mapped logarithmically (−50 dB → 0,
/// 0 dB → 1) so the meter moves naturally with the voice.
enum AudioLevel {
    static func normalizedLevel(from sample: CMSampleBuffer) -> Double? {
        guard let block = CMSampleBufferGetDataBuffer(sample),
              let format = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer, length > 0
        else { return nil }

        var rms: Float = 0
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        if isFloat, asbd.mBitsPerChannel == 32 {
            let count = length / MemoryLayout<Float>.size
            dataPointer.withMemoryRebound(to: Float.self, capacity: count) { ptr in
                vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(count))
            }
        } else if asbd.mBitsPerChannel == 16 {
            let count = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: count) { ptr in
                var floats = [Float](repeating: 0, count: count)
                vDSP_vflt16(ptr, 1, &floats, 1, vDSP_Length(count))
                var scale = Float(1.0 / 32768.0)
                vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(count))
                vDSP_rmsqv(floats, 1, &rms, vDSP_Length(count))
            }
        } else {
            return nil
        }

        guard rms.isFinite, rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return Double(min(max((db + 50) / 50, 0), 1))
    }
}
