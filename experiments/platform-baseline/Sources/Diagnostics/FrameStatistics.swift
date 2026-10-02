import Foundation

/// Disposable probe data: a bounded, in-memory window of monotonic frame intervals.
struct FrameStatistics {
    let capacity: Int
    private(set) var intervals: [TimeInterval] = []
    private var nextIndex = 0
    private var previousTimestamp: TimeInterval?

    init(capacity: Int = 3_600) {
        precondition(capacity > 0)
        self.capacity = capacity
        intervals.reserveCapacity(capacity)
    }

    mutating func record(_ timestamp: TimeInterval) {
        guard timestamp.isFinite else { return }
        defer { previousTimestamp = timestamp }
        guard let previousTimestamp, timestamp > previousTimestamp else { return }
        let interval = timestamp - previousTimestamp
        if intervals.count < capacity {
            intervals.append(interval)
        } else {
            intervals[nextIndex] = interval
            nextIndex = (nextIndex + 1) % capacity
        }
    }

    /// Break the timestamp chain when the scene pauses; suspension is not a frame interval.
    mutating func breakSequence() { previousTimestamp = nil }

    mutating func reset() {
        intervals.removeAll(keepingCapacity: true)
        nextIndex = 0
        previousTimestamp = nil
    }

    var snapshot: Snapshot {
        let sorted = intervals.sorted()
        func percentile(_ fraction: Double) -> TimeInterval {
            guard !sorted.isEmpty else { return 0 }
            return sorted[max(0, Int(ceil(fraction * Double(sorted.count))) - 1)]
        }
        return Snapshot(count: sorted.count, p50: percentile(0.50), p95: percentile(0.95),
                        p99: percentile(0.99), worst: sorted.last ?? 0,
                        over33Milliseconds: sorted.filter { $0 > 0.0333 }.count)
    }

    struct Snapshot {
        let count: Int
        let p50: TimeInterval
        let p95: TimeInterval
        let p99: TimeInterval
        let worst: TimeInterval
        let over33Milliseconds: Int
    }
}
