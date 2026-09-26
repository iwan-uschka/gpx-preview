import Foundation

/// Pure geodesy helpers for the stats line and the renderers.
enum Geo {
    /// Mean Earth radius (IUGG), metres.
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    static func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    static func haversine(_ a: GPXPoint, _ b: GPXPoint) -> Double {
        haversine(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
    }

    /// Summed length of each segment. Never bridges the gap between two
    /// segments.
    static func distance(segments: [[GPXPoint]]) -> Double {
        segments.reduce(0) { total, seg in
            guard seg.count > 1 else { return total }
            var d = 0.0
            for i in 1..<seg.count { d += haversine(seg[i - 1], seg[i]) }
            return total + d
        }
    }

    /// Elevation gain with a hysteresis band: a climb only counts once the
    /// elevation has risen more than `hysteresis` above the last reference
    /// level, which filters GPS altitude jitter. Summed per segment; points
    /// without `<ele>` are skipped. Returns nil when no point has elevation.
    static func elevationGain(segments: [[GPXPoint]], hysteresis: Double = 1) -> Double? {
        var any = false
        var gain = 0.0
        for seg in segments {
            var reference: Double?
            for e in seg.compactMap(\.ele) where e.isFinite {
                any = true
                guard let ref = reference else { reference = e; continue }
                if e - ref > hysteresis {
                    gain += e - ref
                    reference = e
                } else if ref - e > hysteresis {
                    reference = e
                }
            }
        }
        return any ? gain : nil
    }

    /// First-to-last parseable `<time>` in document order, in seconds.
    static func timeSpan(segments: [[GPXPoint]]) -> TimeInterval? {
        let times = segments.flatMap { $0 }.compactMap(\.time)
        guard let first = times.first, let last = times.last, times.count > 1 else { return nil }
        return last.timeIntervalSince(first)
    }
}

/// Lat/lon bounds. When the points straddle the antimeridian the longitudes
/// are shifted into 0…360 so the box stays small; `shiftLongitude` applies
/// the same shift to any point that should be placed in this box.
struct BoundingBox: Equatable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double
    /// True when negative longitudes were shifted by +360.
    var crossesAntimeridian: Bool

    var latSpan: Double { maxLat - minLat }
    var lonSpan: Double { maxLon - minLon }
    var centerLat: Double { (minLat + maxLat) / 2 }
    var centerLon: Double { (minLon + maxLon) / 2 }

    func shiftLongitude(_ lon: Double) -> Double {
        crossesAntimeridian && lon < 0 ? lon + 360 : lon
    }

    /// nil for an empty point list.
    init?(points: [GPXPoint]) {
        guard let first = points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        self.init(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, crossesAntimeridian: false)
        if maxLon - minLon > 180 {
            var sMin = Double.infinity, sMax = -Double.infinity
            for p in points {
                let lon = p.lon < 0 ? p.lon + 360 : p.lon
                sMin = min(sMin, lon); sMax = max(sMax, lon)
            }
            self.minLon = sMin
            self.maxLon = sMax
            self.crossesAntimeridian = true
        }
    }

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, crossesAntimeridian: Bool) {
        self.minLat = minLat; self.maxLat = maxLat
        self.minLon = minLon; self.maxLon = maxLon
        self.crossesAntimeridian = crossesAntimeridian
    }
}
