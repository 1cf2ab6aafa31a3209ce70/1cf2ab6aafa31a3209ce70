/// Renderer-side bookkeeping for the pending-geometry policy. Pure value, no renderer types.
///
/// Policy (rules are authoritative; meshes and collision shapes are views of one field revision):
/// 1. Rules never wait for geometry. Ticks, digs, collection and score keep advancing while
///    a mesh or collision build for revision N is in flight.
/// 2. Each lane (mesh, collision) has at most one build in flight. Changes recorded meanwhile
///    are unioned; the next build targets the latest revision, so intermediate revisions are
///    skipped (coalesced) rather than queued.
/// 3. A completion is installed only if it is the lane's current job of the current
///    generation. Restart starts a new generation; older completions are refused.
/// 4. Collision regeneration may run at a lower cadence: a collision job starts at most once
///    per `collisionInterval` ticks.
/// 5. Input never trusts installed geometry. Touch rays resolve through
///    `ExcavationField.raycast` / `DigRules.digCenter` on the current rule field; a stale
///    collision mesh only affects cosmetic physics until its lane catches up.
///
/// Call `record(_:)` with every report from `advance`, `step` and `restart`, in order.
/// Capture `rules.field` when a job is issued: that value is the field at `job.revision`.
public struct GeometrySync: Sendable, Equatable {
    public enum Lane: Sendable, Equatable { case mesh, collision }

    public struct Job: Sendable, Equatable {
        public let lane: Lane
        public let generation: UInt64
        /// Field revision the build must describe.
        public let revision: UInt64
        /// Chunks to rebuild; chunks outside it are unchanged since their installed revision.
        public let region: DirtyRegion
    }

    /// Minimum ticks between collision job starts (0 means every frame).
    public let collisionInterval: UInt64
    /// Newest rule-field revision recorded.
    public private(set) var latestRevision: UInt64 = 0
    /// Revision of the installed mesh / collision shape; nil before the first install.
    public private(set) var meshRevision: UInt64?
    public private(set) var collisionRevision: UInt64?
    public private(set) var meshInFlight: Job?
    public private(set) var collisionInFlight: Job?
    /// Builds issued per lane, for comparing against the number of revisions.
    public private(set) var meshJobsIssued = 0
    public private(set) var collisionJobsIssued = 0
    private var generation: UInt64 = 0
    private var meshDirty: DirtyRegion
    private var collisionDirty: DirtyRegion
    private var lastCollisionStart: UInt64?

    /// Starts with every chunk dirty at revision 0.
    public init<Field: ExcavationField>(field: Field, collisionInterval: UInt64) {
        self.collisionInterval = collisionInterval
        meshDirty = field.allChunks
        collisionDirty = field.allChunks
    }

    public mutating func record(_ report: DigFrameReport) {
        if report.restarted {
            generation += 1
            meshInFlight = nil
            collisionInFlight = nil
            meshRevision = nil
            collisionRevision = nil
            lastCollisionStart = nil
            meshDirty = report.dirty
            collisionDirty = report.dirty
        } else {
            meshDirty.formUnion(report.dirty)
            collisionDirty.formUnion(report.dirty)
        }
        latestRevision = report.revision
    }

    /// The next mesh build, or nil while one is in flight or nothing changed.
    public mutating func nextMeshJob() -> Job? {
        guard meshInFlight == nil, !meshDirty.isEmpty else { return nil }
        let job = Job(lane: .mesh, generation: generation, revision: latestRevision, region: meshDirty)
        meshDirty = DirtyRegion()
        meshInFlight = job
        meshJobsIssued += 1
        return job
    }

    /// The next collision build, or nil while one is in flight, nothing changed, or fewer
    /// than `collisionInterval` ticks have passed since the previous collision job started.
    public mutating func nextCollisionJob(tick: UInt64) -> Job? {
        guard collisionInFlight == nil, !collisionDirty.isEmpty else { return nil }
        if let last = lastCollisionStart, tick < last &+ collisionInterval { return nil }
        let job = Job(lane: .collision, generation: generation, revision: latestRevision, region: collisionDirty)
        collisionDirty = DirtyRegion()
        collisionInFlight = job
        lastCollisionStart = tick
        collisionJobsIssued += 1
        return job
    }

    /// Returns true if the finished job should be installed; false means discard its output.
    public mutating func complete(_ job: Job) -> Bool {
        guard job.generation == generation else { return false }
        switch job.lane {
        case .mesh:
            guard meshInFlight == job else { return false }
            meshInFlight = nil
            meshRevision = job.revision
        case .collision:
            guard collisionInFlight == job else { return false }
            collisionInFlight = nil
            collisionRevision = job.revision
        }
        return true
    }

    /// A build that failed or was cancelled: its region becomes dirty again.
    public mutating func abandon(_ job: Job) {
        guard job.generation == generation else { return }
        switch job.lane {
        case .mesh:
            guard meshInFlight == job else { return }
            meshInFlight = nil
            meshDirty.formUnion(job.region)
        case .collision:
            guard collisionInFlight == job else { return }
            collisionInFlight = nil
            collisionDirty.formUnion(job.region)
        }
    }

    /// True when the installed mesh describes the latest recorded revision.
    public var isMeshCurrent: Bool { meshRevision == latestRevision && meshInFlight == nil && meshDirty.isEmpty }
    public var isCollisionCurrent: Bool {
        collisionRevision == latestRevision && collisionInFlight == nil && collisionDirty.isEmpty
    }
}
