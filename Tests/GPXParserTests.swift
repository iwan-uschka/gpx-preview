import XCTest

final class GPXParserTests: XCTestCase {

    static func fixture(_ name: String) -> URL {
        let bundle = Bundle(for: GPXParserTests.self)
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = bundle.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures") else {
            fatalError("missing fixture \(name)")
        }
        return url
    }

    private func parse(_ name: String, limits: GPXLimits = .preview) throws -> GPXDocument {
        try GPXParser.parse(url: Self.fixture(name), limits: limits)
    }

    private func assertThrows(_ expected: GPXError, _ name: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parse(name), file: file, line: line) { error in
            XCTAssertEqual(error as? GPXError, expected, file: file, line: line)
        }
    }

    // MARK: - Happy paths

    func testFull11EveryField() throws {
        let doc = try parse("full-1.1.gpx")
        XCTAssertEqual(doc.version, .v1_1)
        XCTAssertEqual(doc.name, "Alpine Loop")
        XCTAssertEqual(doc.title, "Alpine Loop")
        XCTAssertEqual(doc.desc, "Two-day ride around the lake.\nDates: 2026-06-01 to 2026-06-02\nNotes: windy on day two")
        XCTAssertEqual(doc.link, "https://example.com/tours/alpine-loop")
        XCTAssertEqual(doc.keywords, ["bike", "planned", "done"])
        XCTAssertEqual(doc.time, ISO8601DateFormatter().date(from: "2026-06-01T07:00:00Z"))
        XCTAssertEqual(doc.tracks.map(\.name), ["Day 1", "Day 2"])
        XCTAssertEqual(doc.tracks.map { $0.segments.map(\.count) }, [[3, 2], [2, 2]])
        XCTAssertEqual(doc.pointCount, 9)
        XCTAssertEqual(doc.invalidPointCount, 0)
        XCTAssertFalse(doc.truncated)
        let first = doc.tracks[0].segments[0][0]
        XCTAssertEqual(first.lat, 47.0)
        XCTAssertEqual(first.lon, 8.0)
        XCTAssertEqual(first.ele, 400)
        XCTAssertNotNil(first.time)
        // Fractional-second timestamps parse too.
        XCTAssertNotNil(doc.tracks[1].segments[1][0].time)
    }

    func testTitleFallsBackToTrackName() throws {
        let doc = try parse("minimal-no-metadata.gpx")
        XCTAssertNil(doc.name)
        XCTAssertEqual(doc.title, "Morning Ride")
    }

    func testTitleFallsBackToFileName() throws {
        let doc = try parse("unnamed-track.gpx")
        XCTAssertEqual(doc.title, "unnamed-track.gpx")
    }

    func testTitleFallsBackToRouteName() throws {
        let doc = try parse("route-and-waypoints-only.gpx")
        XCTAssertEqual(doc.title, "Planned Route")
    }

    func testTitleOrderPrefersMetadataThenTrackThenRoute() {
        var doc = GPXDocument()
        doc.fileName = "f.gpx"
        doc.routes = [GPXRoute(name: "R", points: [])]
        XCTAssertEqual(doc.title, "R")
        doc.tracks = [GPXTrack(name: "  ", segments: []), GPXTrack(name: "T", segments: [])]
        XCTAssertEqual(doc.title, "T")
        doc.name = "M"
        XCTAssertEqual(doc.title, "M")
    }

    func testGPX10TopLevelMetadataMapsIntoSameModel() throws {
        let doc = try parse("gpx-1.0.gpx")
        XCTAssertEqual(doc.version, .v1_0)
        XCTAssertEqual(doc.name, "Old Format Walk")
        XCTAssertEqual(doc.desc, "Written by a GPX 1.0 tool.")
        XCTAssertEqual(doc.link, "https://example.com/old")
        XCTAssertEqual(doc.keywords, ["walk", "city"])
        XCTAssertEqual(doc.tracks.first?.segments.first?.count, 2)
    }

    func testTrackWithoutSegmentHasZeroSegmentsAndIgnoresStrayPoints() throws {
        let doc = try parse("trk-without-trkseg.gpx")
        XCTAssertEqual(doc.tracks.count, 1)
        XCTAssertEqual(doc.tracks[0].segments.count, 0)
        XCTAssertEqual(doc.pointCount, 0)
        XCTAssertFalse(doc.hasDrawableData)
    }

    func testRouteAndWaypointsCollected() throws {
        let doc = try parse("route-and-waypoints-only.gpx")
        XCTAssertTrue(doc.tracks.isEmpty)
        XCTAssertEqual(doc.routes.count, 1)
        XCTAssertEqual(doc.routes[0].points.count, 3)
        XCTAssertEqual(doc.waypoints.count, 2)
        XCTAssertTrue(doc.hasDrawableData)
    }

    func testNoNamespaceParsedBestEffort() throws {
        let doc = try parse("no-namespace.gpx")
        XCTAssertEqual(doc.version, .unknown)
        XCTAssertEqual(doc.name, "No Namespace")
        XCTAssertEqual(doc.pointCount, 2)
    }

    func testExtensionsContentIgnored() throws {
        let doc = try parse("extensions-heavy.gpx")
        // breaks-if: a <name> or <desc> inside <metadata><extensions> overwrites the real metadata fields
        XCTAssertEqual(doc.name, "With Extensions")
        XCTAssertNil(doc.desc)
        // breaks-if: the decoy <trk> nested under the root-level <extensions> is parsed as a real track
        XCTAssertEqual(doc.tracks.count, 1)
        // breaks-if: a <trk>'s <extensions><name> is used as the track name
        XCTAssertNil(doc.tracks[0].name)
        // breaks-if: a <trkpt>'s nested extension <ele> shadows its real sibling <ele>
        XCTAssertEqual(doc.tracks[0].segments[0].map(\.ele), [10, 12])
        // breaks-if: the decoy trkpt inside the root-level <extensions> is counted as a real point
        XCTAssertEqual(doc.pointCount, 2)
    }

    func testUTF8BOMAccepted() throws {
        let doc = try parse("utf8-bom.gpx")
        XCTAssertEqual(doc.name, "BOM")
        XCTAssertEqual(doc.waypoints.count, 1)
    }

    func testKeywordSplitTrimsDedupesAndKeepsOrder() {
        XCTAssertEqual(GPXParser.splitKeywords(" b, a ,,b\n c\ta "), ["b", "a", "c"])
        XCTAssertEqual(GPXParser.splitKeywords("  ,  "), [])
    }

    // MARK: - Failure paths

    // breaks-if: invalid coordinates are stored instead of skipped, or valid neighbours are dropped with them.
    func testBadCoordinatesSkippedAndCounted() throws {
        let doc = try parse("bad-coords.gpx")
        XCTAssertEqual(doc.invalidPointCount, 5)
        let seg = try XCTUnwrap(doc.tracks.first?.segments.first)
        XCTAssertEqual(seg.map(\.lat), [10, 11])
    }

    // breaks-if: the range check uses exclusive bounds and rejects the exact poles / antimeridian.
    func testCoordinateBoundariesInclusive() {
        XCTAssertNotNil(GPXParser.coordinate(lat: "90", lon: "180"))
        XCTAssertNotNil(GPXParser.coordinate(lat: "-90", lon: "-180"))
        XCTAssertNil(GPXParser.coordinate(lat: "90.0000001", lon: "0"))
        XCTAssertNil(GPXParser.coordinate(lat: "0", lon: "-180.0000001"))
        XCTAssertNil(GPXParser.coordinate(lat: "inf", lon: "0"))
        XCTAssertNil(GPXParser.coordinate(lat: nil, lon: "0"))
    }

    // breaks-if: the parser reports the error position after draining the stream instead of where libxml2 stopped.
    func testMalformedReportsLine() {
        XCTAssertThrowsError(try parse("malformed-unclosed.gpx")) { error in
            guard case let .malformedXML(line, _) = error as? GPXError else {
                return XCTFail("expected malformedXML, got \(error)")
            }
            XCTAssertEqual(line, 7)
        }
    }

    // breaks-if: the root-element check is dropped and any XML document is accepted as an empty GPX.
    func testNotGPXRejected() {
        assertThrows(.notGPX, "not-gpx.xml")
    }

    // breaks-if: the DTD entity callbacks stop aborting, letting the entity expand.
    func testEntityBombAbortedPromptly() {
        let start = Date()
        assertThrows(.entityDeclaration, "entity-bomb.gpx")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    // breaks-if: the empty-file guard is removed and a zero-byte file yields an empty document.
    func testEmptyFileRejected() {
        assertThrows(.notGPX, "empty.gpx")
        XCTAssertThrowsError(try GPXParser.parse(data: Data(), limits: .preview)) {
            XCTAssertEqual($0 as? GPXError, .notGPX)
        }
    }

    // breaks-if: a missing file surfaces as a crash or a generic NSError instead of .unreadable.
    func testMissingFileIsUnreadable() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).gpx")
        XCTAssertThrowsError(try GPXParser.parse(url: url, limits: .preview)) { error in
            guard case .unreadable = error as? GPXError else { return XCTFail("got \(error)") }
        }
    }

    // breaks-if: the isRegularFile guard in parse(url:) is removed or its condition inverted.
    func testDirectoryURLIsUnreadable() {
        let url = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try GPXParser.parse(url: url, limits: .preview)) { error in
            XCTAssertEqual(error as? GPXError, .unreadable("not a regular file"))
        }
    }

    // breaks-if: text is kept in one shared buffer that a stray child element's start or end resets.
    func testStrayChildElementKeepsParentText() throws {
        let data = Data("<gpx version=\"1.1\"><metadata><name>Hello<foo/>World</name></metadata></gpx>".utf8)
        let doc = try GPXParser.parse(data: data, limits: .preview)
        XCTAssertEqual(doc.name, "HelloWorld")
    }

    // breaks-if: truncated XML without a closing root tag is accepted as a valid document.
    func testTruncatedDocumentIsMalformed() {
        let data = Data("<gpx version=\"1.1\"><trk><trkseg><trkpt lat=\"1\" lon=\"1\"/>".utf8)
        XCTAssertThrowsError(try GPXParser.parse(data: data, limits: .preview)) { error in
            guard case .malformedXML = error as? GPXError else { return XCTFail("got \(error)") }
        }
    }

    // Idempotency: parsing is a pure function of the bytes.
    func testParsingTwiceGivesEqualDocuments() throws {
        XCTAssertEqual(try parse("full-1.1.gpx"), try parse("full-1.1.gpx"))
    }
}
