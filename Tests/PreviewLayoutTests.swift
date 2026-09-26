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
        let capped = PreviewLayout.contentSize(for: doc, diagnostic: nil).height
        doc.desc = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let twelve = PreviewLayout.contentSize(for: doc, diagnostic: nil).height
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

    func testImageBlanknessHeuristic() {
        let uniform = RenderSmokeTests.bitmap(CGSize(width: 64, height: 64))
        uniform.setFillColor(CGColor(gray: 0.9, alpha: 1))
        uniform.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(ImageStats.isBlank(uniform.makeImage()!))

        let busy = RenderSmokeTests.bitmap(CGSize(width: 64, height: 64))
        busy.setFillColor(CGColor(gray: 0.9, alpha: 1))
        busy.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        busy.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        busy.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        XCTAssertFalse(ImageStats.isBlank(busy.makeImage()!))
    }
}
