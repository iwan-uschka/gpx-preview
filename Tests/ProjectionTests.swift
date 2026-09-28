import XCTest

final class ProjectionTests: XCTestCase {

    private func box(_ points: [(Double, Double)]) -> BoundingBox {
        BoundingBox(points: points.map { GPXPoint(lat: $0.0, lon: $0.1, ele: nil, time: nil) })!
    }

    func testAspectRatioPreservedAndPadded() {
        // 1° lat × 1° lon at the equator: a square, fitted into a wide rect.
        let b = box([(0, 0), (1, 1)])
        let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
        let proj = Projection.fit(b, into: rect)
        let sw = proj.project(lat: 0, lon: 0), ne = proj.project(lat: 1, lon: 1)
        let w = ne.x - sw.x, h = ne.y - sw.y
        XCTAssertEqual(w / h, CGFloat(cos(0.5 * Double.pi / 180)), accuracy: 1e-6)
        // Height-limited: 8% padding top and bottom.
        XCTAssertEqual(h, 200 * 0.84, accuracy: 1e-6)
        // Centred horizontally.
        XCTAssertEqual((sw.x + ne.x) / 2, 200, accuracy: 1e-6)
    }

    func testNorthIsUpByDefaultAndDownWhenFlipped() {
        let b = box([(0, 0), (1, 1)])
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertGreaterThan(Projection.fit(b, into: rect).project(lat: 1, lon: 0).y,
                             Projection.fit(b, into: rect).project(lat: 0, lon: 0).y)
        XCTAssertLessThan(Projection.fit(b, into: rect, yDown: true).project(lat: 1, lon: 0).y,
                          Projection.fit(b, into: rect, yDown: true).project(lat: 0, lon: 0).y)
    }

    func testHighLatitudeScalesXByCosLat() {
        let b = box([(69.5, 10), (70.5, 11)])
        let proj = Projection.fit(b, into: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let dx = proj.project(lat: 70, lon: 11).x - proj.project(lat: 70, lon: 10).x
        let dy = proj.project(lat: 70.5, lon: 10).y - proj.project(lat: 69.5, lon: 10).y
        XCTAssertEqual(dx / dy, CGFloat(cos(70 * Double.pi / 180)), accuracy: 1e-6)
    }

    // breaks-if: the degenerate-box fallback is removed and scale becomes inf/NaN.
    func testSinglePointCentredWithoutNaN() {
        let b = box([(47, 8), (47, 8)])
        let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
        let proj = Projection.fit(b, into: rect)
        let pt = proj.project(lat: 47, lon: 8)
        XCTAssertEqual(pt.x, rect.midX, accuracy: 1e-9)
        XCTAssertEqual(pt.y, rect.midY, accuracy: 1e-9)
        XCTAssertTrue(proj.scale.isFinite && proj.scale > 0)
        XCTAssertTrue(proj.metresPerPoint.isFinite && proj.metresPerPoint > 0)
    }

    // breaks-if: a zero span on one axis divides by zero instead of fitting the other axis.
    func testNorthSouthLineFitsHeight() {
        let b = box([(0, 5), (1, 5)])
        let proj = Projection.fit(b, into: CGRect(x: 0, y: 0, width: 100, height: 100))
        let h = proj.project(lat: 1, lon: 5).y - proj.project(lat: 0, lon: 5).y
        XCTAssertEqual(h, 84, accuracy: 1e-6)
    }

    func testAntimeridianTrackProjectsContiguously() {
        let b = box([(0, 179.9), (0, -179.9)])
        let proj = Projection.fit(b, into: CGRect(x: 0, y: 0, width: 100, height: 100))
        let a = proj.project(lat: 0, lon: 179.9), c = proj.project(lat: 0, lon: -179.9)
        XCTAssertEqual(c.x - a.x, 84, accuracy: 1e-6)
    }

    func testMetresPerPointMatchesHaversine() {
        let b = box([(0, 0), (1, 0)])
        let proj = Projection.fit(b, into: CGRect(x: 0, y: 0, width: 100, height: 100))
        // 84 points of height span 1° of latitude ≈ 111.2 km.
        XCTAssertEqual(proj.metresPerPoint * 84, 111_195, accuracy: 111_195 * 0.005)
    }

    func testNiceScaleBarLengths() {
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: 2_700), 2_000)
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: 7_000), 5_000)
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: 1_000), 1_000)
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: 0), 0)
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: -5), 0)
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: .nan), 0)
        // breaks-if: niceLength drops its `isFinite` guard (infinity passes `> 0` and comes back as infinity).
        XCTAssertEqual(TrackRenderer.niceLength(maxMetres: .infinity), 0)
        XCTAssertEqual(TrackRenderer.formatDistance(2_000), "2 km")
        XCTAssertEqual(TrackRenderer.formatDistance(1_500), "1.5 km")
        // Non-round values from 10 km up drop the decimal.
        XCTAssertEqual(TrackRenderer.formatDistance(12_345), "12 km")
        XCTAssertEqual(TrackRenderer.formatDistance(500), "500 m")
    }
}
