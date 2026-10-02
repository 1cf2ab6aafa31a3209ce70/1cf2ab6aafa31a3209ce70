import Foundation
import XCTest
@testable import GamePlatform

final class AuthoredAudioTests: XCTestCase {
    func testAllOriginalAudioIsPlayablePCMWithBoundedSamplesAndQuietLoopSeams() {
        let waves = [AuthoredAudio.cue(.selection), AuthoredAudio.cue(.success),
                     AuthoredAudio.cue(.failure), AuthoredAudio.music()]
        for data in waves {
            XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
            XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
            XCTAssertEqual(integer(data, at: 4, bytes: 4), UInt32(data.count - 8))
            XCTAssertEqual(integer(data, at: 20, bytes: 2), 1, "Integer PCM")
            XCTAssertEqual(integer(data, at: 22, bytes: 2), 1, "One channel")
            XCTAssertEqual(integer(data, at: 24, bytes: 4), 22_050)
            XCTAssertEqual(integer(data, at: 34, bytes: 2), 16, "16-bit samples")
            XCTAssertEqual(integer(data, at: 40, bytes: 4), UInt32(data.count - 44))
            let samples = stride(from: 44, to: data.count, by: 2).map {
                Int16(bitPattern: UInt16(integer(data, at: $0, bytes: 2)))
            }
            XCTAssertGreaterThan(samples.count, 1_000)
            XCTAssertEqual(samples.first, 0)
            XCTAssertEqual(samples.last, 0, "Loop/sample boundaries avoid a click")
            XCTAssertTrue(samples.contains { abs(Int($0)) > 100 }, "Content is audible rather than empty PCM")
            XCTAssertTrue(samples.allSatisfy { abs(Int($0)) < 10_000 }, "Placeholder output has headroom")
        }
    }

    private func integer(_ data: Data, at offset: Int, bytes: Int) -> UInt32 {
        (0..<bytes).reduce(0) { $0 | (UInt32(data[offset + $1]) << ($1 * 8)) }
    }
}
