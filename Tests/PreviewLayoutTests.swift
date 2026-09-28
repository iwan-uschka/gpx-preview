import XCTest

final class PreviewLayoutTests: XCTestCase {

    func testStatsLineForFullFixture() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("full-1.1.gpx"), limits: .preview)
        let line = PreviewLayout.statsLine(doc)
        XCTAssertTrue(line.hasPrefix("9 points · "), line)
        XCTAssertTrue(line.contains("↑ "), line)
        XCTAssertTrue(line.contains(" d "), line)  // spans two days
        XCTAssertFalse(line.contains("truncated"), line)
    }

    // breaks-if: truncation / invalid-point notes are dropped from the stats line.
    func testStatsLineCarriesNotes() {
        var doc = GPXDocument()
        doc.truncated = true
        doc.invalidPointCount = 1_234
        let line = PreviewLayout.statsLine(doc)
        XCTAssertTrue(line.contains("(truncated)"), line)
        XCTAssertTrue(line.contains("1,234 invalid points skipped"), line)
        doc.invalidPointCount = 1
        XCTAssertTrue(PreviewLayout.statsLine(doc).contains("1 invalid point skipped"))
    }

    // breaks-if: the `count == 1` pluralisation ternary in statsLine is inverted or dropped.
    func testStatsLineSingularAndZeroPointCounts() {
        var doc = GPXDocument()
        doc.waypoints = [GPXPoint(lat: 0, lon: 0)]
        // A lone waypoint has no distance, elevation, time or notes, so the count is the whole line.
        XCTAssertEqual(PreviewLayout.statsLine(doc), "1 point")
        XCTAssertEqual(PreviewLayout.statsLine(GPXDocument()), "0 points")
    }

    // breaks-if: the two note conditions in notes(_:) are merged, so one flag alone no longer yields its note.
    func testStatsLineCarriesEachNoteAlone() {
        var truncatedOnly = GPXDocument()
        truncatedOnly.truncated = true
        let t = PreviewLayout.statsLine(truncatedOnly)
        XCTAssertTrue(t.contains("(truncated)"), t)
        XCTAssertFalse(t.contains("skipped"), t)
        var invalidOnly = GPXDocument()
        invalidOnly.invalidPointCount = 3
        let i = PreviewLayout.statsLine(invalidOnly)
        XCTAssertTrue(i.contains("3 invalid points skipped"), i)
        XCTAssertFalse(i.contains("(truncated)"), i)
    }

    func testStatsLineOmitsElevationAndTimeWhenAbsent() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("minimal-no-metadata.gpx"), limits: .preview)
        let line = PreviewLayout.statsLine(doc)
        XCTAssertFalse(line.contains("↑"), line)
        XCTAssertFalse(line.contains("min"), line)
        XCTAssertTrue(line.hasPrefix("2 points"), line)
    }

    func testDurationFormatting() {
        XCTAssertEqual(PreviewLayout.formatDuration(45), "45 s")
        XCTAssertEqual(PreviewLayout.formatDuration(60), "1 min")
        XCTAssertEqual(PreviewLayout.formatDuration(3_600 * 2 + 13 * 60), "2 h 13 min")
        XCTAssertEqual(PreviewLayout.formatDuration(86_400 + 3_600 * 4), "1 d 4 h")
    }

    // breaks-if: the description cap is removed and a long desc grows the page unbounded.
    func testDescriptionCappedAtTwelveLines() {
        var doc = GPXDocument()
        doc.desc = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let capped = PreviewLayout.contentSize(for: doc).height
        doc.desc = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let twelve = PreviewLayout.contentSize(for: doc).height
        XCTAssertEqual(capped, twelve)
        let lines = TextDrawing.wrap((1...40).map { "l\($0)" }.joined(separator: "\n"),
                                     width: 500, font: TextDrawing.font(size: 13), maxLines: 12)
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.last!.hasSuffix("…"))
    }

    func testErrorTextNamesLine() {
        XCTAssertEqual(PreviewLayout.errorText(GPXError.malformedXML(line: 12, column: 4)),
                       "Couldn't read GPX: malformed XML at line 12, column 4")
    }

    // breaks-if: errorText drops the `?? error.localizedDescription` fallback for non-GPXError errors.
    func testErrorTextFallsBackToLocalizedDescriptionForNonGPXError() {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        XCTAssertEqual(PreviewLayout.errorText(Boom()), "Couldn't read GPX: boom")
    }

    func testErrorMessageForEveryOtherCase() {
        XCTAssertEqual(GPXError.notGPX.message, "not a GPX file")
        XCTAssertEqual(GPXError.noDrawableData.message, "no track data")
        XCTAssertEqual(GPXError.limitExceeded(.fileSize).message, "file is too large")
        XCTAssertEqual(GPXError.limitExceeded(.elements).message, "file has too many XML elements")
        XCTAssertEqual(GPXError.timedOut.message, "parsing took too long")
        XCTAssertEqual(GPXError.entityDeclaration.message, "file declares XML entities, which GPX never uses")
        XCTAssertEqual(GPXError.unreadable("x").message, "file could not be read (x)")
    }
}
