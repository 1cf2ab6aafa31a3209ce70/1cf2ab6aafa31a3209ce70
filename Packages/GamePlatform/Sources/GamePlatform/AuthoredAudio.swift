import Foundation

/// Original placeholder notes generated in RAM. No recordings, asset files,
/// network access, or third-party material are needed by the shell sample.
enum AuthoredAudio {
    static let sampleRate = 22_050

    static func cue(_ cue: ShellFeedbackCue) -> Data {
        switch cue {
        case .selection: return wave(notes: [660], noteDuration: 0.06, amplitude: 0.25)
        case .success: return wave(notes: [523.25, 659.25, 783.99], noteDuration: 0.1, amplitude: 0.2)
        case .failure: return wave(notes: [392, 261.63], noteDuration: 0.12, amplitude: 0.2)
        }
    }

    static func music() -> Data {
        wave(notes: [261.63, 329.63, 392, 329.63, 293.66, 349.23, 440, 349.23],
             noteDuration: 0.5, amplitude: 0.1)
    }

    private static func wave(notes: [Double], noteDuration: Double, amplitude: Double) -> Data {
        let samplesPerNote = Int(Double(sampleRate) * noteDuration)
        let sampleCount = samplesPerNote * notes.count
        let byteCount = UInt32(sampleCount * 2)
        var result = Data()
        result.reserveCapacity(44 + Int(byteCount))
        result.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + byteCount, to: &result)
        result.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &result) // PCM format chunk
        append(UInt16(1), to: &result)  // integer PCM
        append(UInt16(1), to: &result)  // mono
        append(UInt32(sampleRate), to: &result)
        append(UInt32(sampleRate * 2), to: &result)
        append(UInt16(2), to: &result)  // block alignment
        append(UInt16(16), to: &result)
        result.append(contentsOf: "data".utf8)
        append(byteCount, to: &result)
        for frequency in notes {
            for sample in 0..<samplesPerNote {
                let elapsed = Double(sample) / Double(sampleRate)
                let remaining = Double(samplesPerNote - 1 - sample) / Double(sampleRate)
                let envelope = min(1, min(elapsed / 0.01, remaining / 0.02))
                let value = amplitude * envelope * sin(2 * .pi * frequency * elapsed)
                append(Int16(value * Double(Int16.max)), to: &result)
            }
        }
        return result
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
