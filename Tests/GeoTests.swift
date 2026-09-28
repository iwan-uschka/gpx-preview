import XCTest

final class GeoTests: XCTestCase {

    private func p(_ lat: Double, _ lon: Double, ele: Double? = nil) -> GPXPoint {
        GPXPoint(lat: lat, lon: lon, ele: ele, time: nil)
    }

    private func assertWithin(_ value: Double, _ expected: Double, fraction: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(abs(value - expected) / expected, fraction, "\(value) vs \(expected)", file: file, line: line)
    }

    func testHaversineKnownCityPairs() {
        // Reference great-circle distances.
        assertWithin(Geo.haversine(lat1: 51.5074, lon1: -0.1278, lat2: 48.8566, lon2: 2.3522), 343_500, fraction: 0.005)
        assertWithin(Geo.haversine(lat1: 52.5200, lon1: 13.4050, lat2: 48.1351, lon2: 11.5820), 504_000, fraction: 0.005)
        assertWithin(Geo.haversine(lat1: 40.7128, lon1: -74.0060, lat2: 34.0522, lon2: -118.2437), 3_936_000, fraction: 0.005)
        XCTAssertEqual(Geo.haversine(lat1: 10, lon1: 10, lat2: 10, lon2: 10), 0)
    }

    // breaks-if: distance sums across the gap between two segments.
    func testSegmentGapsNotBridged() {
        let a = [p(0, 0), p(0, 0.01)]
        let b = [p(10, 10), p(10, 10.01)]
        let joined = Geo.distance(segments: [a, b])
        let separate = Geo.distance(segments: [a]) + Geo.distance(segments: [b])
        XCTAssertEqual(joined, separate, accuracy: 1e-6)
        XCTAssertLessThan(joined, 5_000)
    }

    // breaks-if: the `guard seg.count > 1` short-circuit in Geo.distance is removed.
    func testSinglePointSegmentHasZeroDistance() {
        XCTAssertEqual(Geo.distance(segments: [[p(1, 1)], []]), 0)
    }

    // breaks-if: the hysteresis band is removed and sub-metre jitter counts as climbing.
    func testElevationJitterBelowHysteresisIgnored() {
        let jitter = [100, 100.6, 100.1, 100.9, 100.2, 100.8].map { p(0, 0, ele: $0) }
        XCTAssertEqual(Geo.elevationGain(segments: [jitter]), 0)
    }

    func testElevationGainCountsRealClimbs() throws {
        let climb = [100, 105, 103, 110, 90, 95].map { p(0, 0, ele: $0) }
        // 100→105 (+5), drop to 103 (beyond the band: new reference), 103→110 (+7), drop to 90, 90→95 (+5)
        let gain = try XCTUnwrap(Geo.elevationGain(segments: [climb]))
        XCTAssertEqual(gain, 17, accuracy: 1e-9)
    }

    // breaks-if: the climb comparison in elevationGain becomes `>=` and a rise of exactly `hysteresis` counts.
    func testElevationGainExactlyAtHysteresisNotCounted() {
        let points = [p(0, 0, ele: 100), p(0, 0, ele: 101)] // delta == hysteresis
        XCTAssertEqual(Geo.elevationGain(segments: [points]), 0)
    }

    // breaks-if: elevation gain bridges segments and counts the jump between them.
    func testElevationGainNotBridgedAcrossSegments() {
        let a = [p(0, 0, ele: 100), p(0, 0, ele: 100)]
        let b = [p(0, 0, ele: 500), p(0, 0, ele: 500)]
        XCTAssertEqual(Geo.elevationGain(segments: [a, b]), 0)
    }

    // breaks-if: elevationGain returns 0 instead of nil when no point has `<ele>`.
    func testElevationGainNilWithoutElevation() {
        XCTAssertNil(Geo.elevationGain(segments: [[p(0, 0), p(1, 1)]]))
    }

    // breaks-if: the isFinite filter in elevationGain is dropped and NaN/Infinity poison the sum.
    func testElevationGainSkipsNonFiniteElevations() {
        let seg = [p(0, 0, ele: 100), p(0, 0, ele: .nan), p(0, 0, ele: .infinity), p(0, 0, ele: 110)]
        XCTAssertEqual(Geo.elevationGain(segments: [seg]), 10)
        XCTAssertNil(Geo.elevationGain(segments: [[p(0, 0, ele: .nan), p(0, 0, ele: -.infinity)]]))
    }

    func testTimeSpanFirstToLast() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var a = p(0, 0); a.time = t0
        let b = p(0, 0)
        var c = p(0, 0); c.time = t0.addingTimeInterval(3_600)
        XCTAssertEqual(Geo.timeSpan(segments: [[a, b], [c]]), 3_600)
        // breaks-if: timeSpan drops its `times.count > 1` guard and returns 0 for a single timestamp.
        XCTAssertNil(Geo.timeSpan(segments: [[a, b]]))
    }

    // breaks-if: the antimeridian shift is dropped and the box spans ~360°.
    func testAntimeridianBoundingBox() throws {
        let box = try XCTUnwrap(BoundingBox(points: [p(-17, 179.9), p(-17.1, -179.9)]))
        XCTAssertTrue(box.crossesAntimeridian)
        XCTAssertEqual(box.lonSpan, 0.2, accuracy: 1e-9)
        XCTAssertEqual(box.shiftLongitude(-179.9), 180.1, accuracy: 1e-9)
    }

    // breaks-if: the crossing test uses >= 180 and shifts a box of exactly 180° span.
    func testExactly180SpanNotShifted() throws {
        let box = try XCTUnwrap(BoundingBox(points: [p(0, -90), p(0, 90)]))
        XCTAssertFalse(box.crossesAntimeridian)
        XCTAssertEqual(box.lonSpan, 180)
    }

    // breaks-if: BoundingBox.init(points:) stops returning nil for an empty array.
    func testEmptyBoundingBoxIsNil() {
        XCTAssertNil(BoundingBox(points: []))
    }
}
