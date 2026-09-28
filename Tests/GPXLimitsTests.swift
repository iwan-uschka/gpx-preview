import XCTest

/// Large inputs are generated here at test time, never committed.
final class GPXLimitsTests: XCTestCase {

    static func gpx(points: Int) -> Data {
        var s = "<?xml version=\"1.0\"?>\n<gpx version=\"1.1\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><trkseg>\n"
        s.reserveCapacity(points * 40 + 200)
        for i in 0..<points {
            let lat = 45 + Double(i % 1000) * 0.0001
            let lon = 7 + Double(i / 1000) * 0.0001
            s += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"/>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        return Data(s.utf8)
    }

    private static func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("limit-\(UUID().uuidString).gpx")
        let head = "<gpx version=\"1.1\"><!--"
        let tail = "--></gpx>"
        let body = String(repeating: "x", count: bytes - head.utf8.count - tail.utf8.count)
        try Data((head + body + tail).utf8).write(to: url)
        return url
    }

    // breaks-if: the stored-points cap stops being enforced, or truncation is not flagged.
    func testThumbnailPresetTruncatesAtStoredPointCap() throws {
        var limits = GPXLimits.thumbnail
        limits.deadline = .seconds(30) // decouple from the stored-points cap under test
        let doc = try GPXParser.parse(data: Self.gpx(points: 300_000), limits: limits)
        XCTAssertTrue(doc.truncated)
        XCTAssertEqual(doc.pointCount, GPXLimits.thumbnail.maxStoredPoints)
    }

    // breaks-if: the cap check is off by one (stores cap+1, or flags truncation at exactly cap points).
    func testExactlyCapPointsIsNotTruncated() throws {
        var limits = GPXLimits.preview
        limits.maxStoredPoints = 10
        let atCap = try GPXParser.parse(data: Self.gpx(points: 10), limits: limits)
        XCTAssertFalse(atCap.truncated)
        XCTAssertEqual(atCap.pointCount, 10)
        let overCap = try GPXParser.parse(data: Self.gpx(points: 11), limits: limits)
        XCTAssertTrue(overCap.truncated)
        XCTAssertEqual(overCap.pointCount, 10)
    }

    // breaks-if: the element counter is removed, or elements inside <extensions> stop counting.
    func testElementFloodAborts() {
        var s = "<gpx version=\"1.1\"><extensions>"
        s += String(repeating: "<x/>", count: 2_000)
        s += "</extensions></gpx>"
        var limits = GPXLimits.preview
        limits.maxElements = 1_000
        XCTAssertThrowsError(try GPXParser.parse(data: Data(s.utf8), limits: limits)) {
            XCTAssertEqual($0 as? GPXError, .limitExceeded(.elements))
        }
    }

    // breaks-if: the element-count comparison in GPXParser is off by one in either direction.
    func testElementCapIsExactBoundary() throws {
        var limits = GPXLimits.preview
        // gpx(points: 1) has exactly four start elements: gpx, trk, trkseg, trkpt.
        limits.maxElements = 4
        XCTAssertNoThrow(try GPXParser.parse(data: Self.gpx(points: 1), limits: limits))
        limits.maxElements = 3
        XCTAssertThrowsError(try GPXParser.parse(data: Self.gpx(points: 1), limits: limits)) {
            XCTAssertEqual($0 as? GPXError, .limitExceeded(.elements))
        }
    }

    // breaks-if: the file-size check moves after opening the stream, or compares against the wrong limit.
    func testFileSizeCapThrowsBeforeParsing() throws {
        let url = try Self.tempFile(bytes: 2048)
        defer { try? FileManager.default.removeItem(at: url) }
        var limits = GPXLimits.preview
        limits.maxFileSize = 1024
        XCTAssertThrowsError(try GPXParser.parse(url: url, limits: limits)) {
            XCTAssertEqual($0 as? GPXError, .limitExceeded(.fileSize))
        }
        // Same file at a limit equal to its size is allowed through to parsing.
        limits.maxFileSize = 2048
        XCTAssertNoThrow(try GPXParser.parse(url: url, limits: limits))
    }

    // breaks-if: the deadline is never checked, or checked against the real clock instead of the injected one.
    func testDeadlineWithFakeClockTimesOut() {
        let base = ContinuousClock.now
        var ticks = 0
        let fakeNow: () -> ContinuousClock.Instant = {
            ticks += 1
            return base.advanced(by: .seconds(ticks))
        }
        let data = Self.gpx(points: 5_000)
        XCTAssertThrowsError(try GPXParser.parse(data: data, limits: .thumbnail, now: fakeNow)) {
            XCTAssertEqual($0 as? GPXError, .timedOut)
        }
    }

    // breaks-if: the per-element text cap is dropped and a huge <desc> is kept whole.
    func testTextPerElementCapped() throws {
        var limits = GPXLimits.preview
        limits.maxTextPerElement = 100
        let s = "<gpx version=\"1.1\"><metadata><desc>" + String(repeating: "a", count: 5_000)
            + "</desc></metadata></gpx>"
        let doc = try GPXParser.parse(data: Data(s.utf8), limits: limits)
        XCTAssertEqual(doc.desc?.count, 100)
    }

    /// Criterion 4 support: ~10,000 points (about 1 MB) parse + lay out fast.
    func testTenThousandPointsParseAndLayoutUnderOneSecond() throws {
        var s = "<?xml version=\"1.0\"?>\n<gpx version=\"1.1\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><trkseg>\n"
        for i in 0..<10_000 {
            let lat = 47 + sin(Double(i) / 500) * 0.05
            let lon = 8 + Double(i) * 0.00002
            s += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(400 + i % 50)</ele>"
                + "<time>2026-06-01T07:\(String(format: "%02d", (i / 60) % 60)):\(String(format: "%02d", i % 60))Z</time></trkpt>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        let data = Data(s.utf8)
        XCTAssertGreaterThan(data.count, 900_000)

        let start = ContinuousClock.now
        let doc = try GPXParser.parse(data: data, limits: .preview)
        let size = PreviewLayout.contentSize(for: doc)
        let ctx = RenderSmokeTests.bitmap(size)
        PreviewLayout.draw(doc, in: ctx, size: size)
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(doc.pointCount, 10_000)
        XCTAssertLessThan(elapsed, .seconds(1), "took \(elapsed)")
    }
}
