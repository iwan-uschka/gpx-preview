import Foundation

/// One validated GPX point (`trkpt`, `rtept` or `wpt`).
struct GPXPoint: Equatable {
    var lat: Double
    var lon: Double
    var ele: Double?
    var time: Date?
}

struct GPXTrack: Equatable {
    var name: String?
    /// One array per `<trkseg>`. Gaps between segments are real gaps: nothing
    /// (drawing, distance, elevation) bridges them.
    var segments: [[GPXPoint]]
}

struct GPXRoute: Equatable {
    var name: String?
    var points: [GPXPoint]
}

enum GPXVersion: Equatable {
    case v1_0
    case v1_1
    case unknown
}

/// Everything the renderers need from a GPX file. GPX 1.0 and 1.1 metadata
/// (top-level vs. `<metadata>`) map into the same fields.
struct GPXDocument: Equatable {
    var version: GPXVersion = .unknown
    var name: String?
    var desc: String?
    /// `metadata/link@href` (1.1) or top-level `url` (1.0).
    var link: String?
    var keywords: [String] = []
    var time: Date?
    var tracks: [GPXTrack] = []
    var routes: [GPXRoute] = []
    var waypoints: [GPXPoint] = []
    /// The stored-points limit was hit; later points were dropped.
    var truncated = false
    /// Points skipped for a missing, non-finite or out-of-range coordinate.
    var invalidPointCount = 0
    /// Last path component of the source file, for the title fallback.
    var fileName: String?

    /// Header title: `metadata/name`, then first `trk/name`, then first
    /// `rte/name`, then the file name.
    var title: String {
        if let name = name.nonBlank { return name }
        if let trk = tracks.lazy.compactMap({ $0.name.nonBlank }).first { return trk }
        if let rte = routes.lazy.compactMap({ $0.name.nonBlank }).first { return rte }
        return fileName ?? "Untitled"
    }

    var trackSegments: [[GPXPoint]] { tracks.flatMap(\.segments) }

    /// Every stored point, in document order (tracks, routes, waypoints).
    var allPoints: [GPXPoint] {
        trackSegments.flatMap { $0 } + routes.flatMap(\.points) + waypoints
    }

    var pointCount: Int {
        trackSegments.reduce(0) { $0 + $1.count }
            + routes.reduce(0) { $0 + $1.points.count }
            + waypoints.count
    }

    var hasDrawableData: Bool { pointCount > 0 }
}

extension Optional where Wrapped == String {
    /// The trimmed string, or nil when absent or whitespace-only.
    var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
