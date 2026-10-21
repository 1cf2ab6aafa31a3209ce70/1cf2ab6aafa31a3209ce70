@testable import DigFeasibility
import DigCore
import GameCore
import GamePlatform
import XCTest

@MainActor
final class DigSessionTests: XCTestCase {
    func testRegistersContractVersionOneWithCatalogTitle() {
        let module = DigModule(options: DigOptions())
        XCTAssertEqual(module.contractVersion, 1)
        XCTAssertEqual(module.title.id, "development-practice")
        XCTAssertTrue(ModuleHost<DigModule>.supportedContractVersions.contains(module.contractVersion))
    }

    /// Touch, controls and the trace driver share `submit`; it accepts only while playing.
    func testInputIsGatedByPlayingForEveryCandidate() async throws {
        for candidate in DigCandidate.allCases {
            let session = DigSession(options: DigOptions(candidate: candidate))
            let request = LoadRequest(titleID: "development-practice")
            XCTAssertFalse(session.submit(.digAtCursor), "\(candidate) before load")
            try await session.prepare(for: request)
            session.begin(for: request)
            XCTAssertFalse(session.submit(.digAtCursor), "\(candidate) not playing")
            session.playing = true
            XCTAssertTrue(session.submit(.digAtCursor), "\(candidate) playing")
            XCTAssertTrue(session.submit(.moveCursor(dx: 1, dz: 0)), "\(candidate) playing")
            session.playing = false
            XCTAssertFalse(session.submit(.digAtCursor), "\(candidate) paused")
            XCTAssertEqual(session.engine.probe.pending, 2, "\(candidate) paused ticks run nothing")
        }
    }

    func testRestartRestoresInitialRuleState() async throws {
        let session = DigSession(options: DigOptions(candidate: .heightfield))
        let request = LoadRequest(titleID: "development-practice")
        try await session.prepare(for: request)
        session.begin(for: request)
        let initial = session.engine.probe.digest
        session.playing = true
        XCTAssertTrue(session.submit(.digAtCursor))
        let again = LoadRequest(titleID: "development-practice")
        session.playing = false
        try await session.prepare(for: again)
        session.begin(for: again)
        XCTAssertEqual(session.engine.probe.digest, initial)
        XCTAssertEqual(session.engine.probe.pending, 0)
        XCTAssertTrue(session.engine.probe.restoredInitialState)
    }

    func testRejectsAnotherTitle() async {
        let session = DigSession(options: DigOptions())
        do {
            try await session.prepare(for: LoadRequest(titleID: "another-title"))
            XCTFail("Expected a validation error")
        } catch {}
    }

    func testDebugOptionsParseAndRejectMalformedValues() {
        let options = DigOptions.parse(["app", "--dig-candidate", "voxel", "--dig-run-label", "run1-timing",
                                        "--dig-mesh-delay-ms", "50", "--dig-collision-delay-ms", "200", "--dig-fps", "30"])
        XCTAssertEqual(options.candidate, .voxel)
        XCTAssertEqual(options.runLabel, "run1-timing")
        XCTAssertEqual(options.meshDelay, .milliseconds(50))
        XCTAssertEqual(options.collisionDelay, .milliseconds(200))
        XCTAssertEqual(options.preferredFramesPerSecond, 30)
        let bad = DigOptions.parse(["app", "--dig-candidate", "metal", "--dig-run-label", "../x", "--dig-fps", "7"])
        XCTAssertEqual(bad, DigOptions())
    }
}
