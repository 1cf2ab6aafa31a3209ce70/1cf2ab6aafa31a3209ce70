import XCTest
@testable import BaselineLogic

final class FrameStatisticsTests: XCTestCase {
    func testNearestRankPercentilesAndSlowFrames() {
        var frames = FrameStatistics(capacity: 100)
        var timestamp = 0.0
        frames.record(timestamp)
        for index in 1...100 {
            timestamp += Double(index) / 1_000
            frames.record(timestamp)
        }
        let result = frames.snapshot
        XCTAssertEqual(result.count, 100)
        XCTAssertEqual(result.p50, 0.050, accuracy: 0.000_001)
        XCTAssertEqual(result.p95, 0.095, accuracy: 0.000_001)
        XCTAssertEqual(result.p99, 0.099, accuracy: 0.000_001)
        XCTAssertEqual(result.worst, 0.100, accuracy: 0.000_001)
        XCTAssertEqual(result.over33Milliseconds, 67)
    }

    func testBoundedWindowAndReset() {
        var frames = FrameStatistics(capacity: 2)
        [0.0, 0.01, 0.03, 0.06].forEach { frames.record($0) }
        XCTAssertEqual(frames.snapshot.count, 2)
        XCTAssertEqual(frames.snapshot.p50, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(frames.snapshot.worst, 0.03, accuracy: 0.000_001)
        frames.reset()
        frames.record(50)
        XCTAssertEqual(frames.snapshot.count, 0)
    }

    func testPauseDoesNotCountSuspensionAndNonfiniteTimestampsAreIgnored() {
        var frames = FrameStatistics()
        frames.record(0)
        frames.record(0.01)
        frames.breakSequence()
        frames.record(100)
        frames.record(.nan)
        frames.record(.infinity)
        frames.record(100.02)
        XCTAssertEqual(frames.snapshot.count, 2)
        XCTAssertEqual(frames.snapshot.worst, 0.02, accuracy: 0.000_001)
    }
}
