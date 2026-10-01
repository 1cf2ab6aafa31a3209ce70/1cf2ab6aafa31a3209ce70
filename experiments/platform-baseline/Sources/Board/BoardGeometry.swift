import Foundation

/// SpriteKit coordinates use a lower-left origin. The right/top board edges are exclusive.
struct BoardGeometry {
    let columns: Int
    let rows: Int
    let origin: CGPoint
    let cellSize: CGFloat

    init(columns: Int, rows: Int, viewport: CGSize) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        cellSize = max(1, min((viewport.width - 40) / CGFloat(columns), (viewport.height - 64) / CGFloat(rows)))
        origin = CGPoint(x: (viewport.width - CGFloat(columns) * cellSize) / 2,
                         y: (viewport.height - CGFloat(rows) * cellSize) / 2)
    }

    func center(of index: Int) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(index % columns) + 0.5) * cellSize,
                y: origin.y + (CGFloat(index / columns) + 0.5) * cellSize)
    }

    func index(at point: CGPoint) -> Int? {
        let x = (point.x - origin.x) / cellSize
        let y = (point.y - origin.y) / cellSize
        guard x >= 0, y >= 0, x < CGFloat(columns), y < CGFloat(rows) else { return nil }
        return Int(y) * columns + Int(x)
    }
}
