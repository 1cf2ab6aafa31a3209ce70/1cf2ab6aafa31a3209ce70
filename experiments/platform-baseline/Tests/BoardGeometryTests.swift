import Foundation
import XCTest
@testable import BaselineLogic

final class BoardGeometryTests: XCTestCase {
    func testCellCentersRoundTripAcrossResizeAndModes() {
        for viewport in [CGSize(width: 320, height: 480), CGSize(width: 1024, height: 600), CGSize(width: 600, height: 1024)] {
            for (columns, rows) in [(8, 8), (4, 3)] {
                let geometry = BoardGeometry(columns: columns, rows: rows, viewport: viewport)
                for index in 0..<(columns * rows) {
                    XCTAssertEqual(geometry.index(at: geometry.center(of: index)), index)
                }
            }
        }
    }

    func testOutsideAndExclusiveEdgesDoNotActivateCells() {
        let geometry = BoardGeometry(columns: 8, rows: 8, viewport: CGSize(width: 400, height: 600))
        XCTAssertEqual(geometry.index(at: geometry.origin), 0)
        XCTAssertNil(geometry.index(at: CGPoint(x: geometry.origin.x - 0.01, y: geometry.origin.y)))
        XCTAssertNil(geometry.index(at: CGPoint(x: geometry.origin.x, y: geometry.origin.y - 0.01)))
        XCTAssertNil(geometry.index(at: CGPoint(x: geometry.origin.x + 8 * geometry.cellSize, y: geometry.origin.y)))
        XCTAssertNil(geometry.index(at: CGPoint(x: geometry.origin.x, y: geometry.origin.y + 8 * geometry.cellSize)))
    }
}
