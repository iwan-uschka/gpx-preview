import CoreGraphics
import Foundation

/// Local equirectangular projection for the vector renderer:
/// `x = lon · cos(centreLat)`, `y = lat`, fitted into a rectangle with
/// padding and the aspect ratio preserved.
///
/// Output is in Core Graphics' native y-up space (origin bottom-left), so
/// north is up without a flip when drawing into a plain `CGContext` (PDF,
/// bitmap, Quick Look's reply contexts). `yDown: true` produces the flipped,
/// y-down variant for top-left-origin drawing.
struct Projection {
    let box: BoundingBox
    let scale: CGFloat        // points per projected unit
    let cosLat: Double
    let origin: CGPoint       // where the box centre lands
    let yDown: Bool
    /// Metres represented by one point at the box centre (for the scale bar).
    let metresPerPoint: Double

    static let defaultPadding: CGFloat = 0.08

    /// Fits `box` into `rect`, `padding` being the fraction of each side kept
    /// empty. A degenerate box (one point, or all points identical) lands
    /// centred without dividing by zero.
    static func fit(_ box: BoundingBox, into rect: CGRect,
                    padding: CGFloat = defaultPadding, yDown: Bool = false) -> Projection {
        let cosLat = max(cos(box.centerLat * .pi / 180), 1e-6)
        let spanX = box.lonSpan * cosLat
        let spanY = box.latSpan
        let inner = rect.insetBy(dx: rect.width * padding, dy: rect.height * padding)

        var candidates: [CGFloat] = []
        if spanX > 0 { candidates.append(inner.width / CGFloat(spanX)) }
        if spanY > 0 { candidates.append(inner.height / CGFloat(spanY)) }
        // Degenerate: nothing to fit. Pick a scale that makes ~100 m span the
        // shorter side so the scale bar still reads sensibly.
        let fallback = min(inner.width, inner.height) / CGFloat(100.0 / metresPerDegreeLat(at: box.centerLat))
        let scale = candidates.min() ?? fallback

        return Projection(box: box, scale: scale, cosLat: cosLat,
                          origin: CGPoint(x: rect.midX, y: rect.midY), yDown: yDown,
                          metresPerPoint: metresPerDegreeLat(at: box.centerLat) / Double(scale))
    }

    func project(lat: Double, lon: Double) -> CGPoint {
        let dx = (box.shiftLongitude(lon) - box.centerLon) * cosLat
        let dy = lat - box.centerLat
        let y = CGFloat(dy) * scale
        return CGPoint(x: origin.x + CGFloat(dx) * scale, y: yDown ? origin.y - y : origin.y + y)
    }

    func project(_ p: GPXPoint) -> CGPoint { project(lat: p.lat, lon: p.lon) }

    /// Metres per degree of latitude around `lat`, via haversine (one
    /// projected y unit is one degree of latitude).
    static func metresPerDegreeLat(at lat: Double) -> Double {
        let a = max(-89.5, min(89.5, lat))
        return Geo.haversine(lat1: a - 0.5, lon1: 0, lat2: a + 0.5, lon2: 0)
    }
}
