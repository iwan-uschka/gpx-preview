import XCTest

final class RenderSmokeTests: XCTestCase {

    /// RGBA8 sRGB bitmap context, transparent, y-up.
    static func bitmap(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// (r, g, b, a) at pixel (x, y) in y-up coordinates.
    static func pixel(_ ctx: CGContext, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = ctx.height - 1 - y  // bitmap memory is top-down
        let i = row * ctx.bytesPerRow + x * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    private static func isWhite(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        p.3 == 255 && p.0 > 240 && p.1 > 240 && p.2 > 240
    }

    /// SW→NE diagonal track.
    private let diagonal: GPXDocument = {
        var d = GPXDocument()
        let pts = (0...20).map { i in GPXPoint(lat: 47 + Double(i) * 0.005, lon: 8 + Double(i) * 0.005 / cos(47 * .pi / 180),
                                               ele: nil, time: nil) }
        d.tracks = [GPXTrack(name: "diag", segments: [pts])]
        return d
    }()

    private func assertThumbnail(side: Int, file: StaticString = #filePath, line: UInt = #line) {
        let size = CGSize(width: side, height: side)
        let ctx = Self.bitmap(size)
        XCTAssertTrue(TrackRenderer.drawThumbnail(diagonal, size: size, in: ctx), file: file, line: line)

        // Corner outside the rounded card stays transparent background.
        XCTAssertEqual(Self.pixel(ctx, 0, 0).3, 0, "corner not background", file: file, line: line)
        // Inside the card, off the diagonal, is white card.
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, side * 3 / 4, side / 4)), "card not white", file: file, line: line)
        // Along the diagonal: track pixels.
        var hits = 0
        for f in stride(from: 0.3, through: 0.7, by: 0.1) {
            let c = Int(Double(side) * f)
            let neighbourhood = (-1...1).flatMap { dx in (-1...1).map { dy in Self.pixel(ctx, c + dx, c + dy) } }
            if neighbourhood.contains(where: { !Self.isWhite($0) && $0.3 > 0 }) { hits += 1 }
        }
        XCTAssertEqual(hits, 5, "track not drawn along the diagonal", file: file, line: line)
    }

    func testThumbnail64() { assertThumbnail(side: 64) }
    func testThumbnail512() { assertThumbnail(side: 512) }

    // breaks-if: drawThumbnail draws an empty card for a document without points instead of reporting failure.
    func testThumbnailWithoutPointsReportsNothingToDraw() {
        let ctx = Self.bitmap(CGSize(width: 64, height: 64))
        XCTAssertFalse(TrackRenderer.drawThumbnail(GPXDocument(), size: CGSize(width: 64, height: 64), in: ctx))
        XCTAssertEqual(Self.pixel(ctx, 32, 32).3, 0)
    }

    func testRendererWithFakeProjectionStrokesThroughProjectedPoints() {
        let ctx = Self.bitmap(CGSize(width: 64, height: 64))
        var doc = GPXDocument()
        doc.tracks = [GPXTrack(name: nil, segments: [[GPXPoint(lat: 0, lon: 0), GPXPoint(lat: 1, lon: 0)]])]
        // Identity-ish projection: lat → y, fixed x = 32.
        TrackRenderer.draw(doc, in: ctx, rect: CGRect(x: 0, y: 0, width: 64, height: 64),
                           project: { CGPoint(x: 32, y: 10 + $0.lat * 44) }, style: .preview)
        XCTAssertGreaterThan(Self.pixel(ctx, 32, 32).3, 0)
        XCTAssertEqual(Self.pixel(ctx, 5, 32).3, 0)
    }

    // breaks-if: segments are joined into one polyline, bridging the gap between them.
    func testSegmentGapStaysEmpty() {
        let ctx = Self.bitmap(CGSize(width: 100, height: 20))
        var doc = GPXDocument()
        let a = [GPXPoint(lat: 0, lon: 0), GPXPoint(lat: 0, lon: 1)]
        let b = [GPXPoint(lat: 0, lon: 4), GPXPoint(lat: 0, lon: 5)]
        doc.tracks = [GPXTrack(name: nil, segments: [a, b])]
        var style = TrackRenderer.Style.preview
        style.endpointRadius = 0
        TrackRenderer.draw(doc, in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                           project: { CGPoint(x: 10 + $0.lon * 16, y: 10) }, style: style)
        XCTAssertGreaterThan(Self.pixel(ctx, 18, 10).3, 0)  // inside segment a
        XCTAssertEqual(Self.pixel(ctx, 50, 10).3, 0)        // gap
        XCTAssertGreaterThan(Self.pixel(ctx, 82, 10).3, 0)  // inside segment b
    }

    func testPreviewLayoutDrawsWithoutCrashing() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("full-1.1.gpx"), limits: .preview)
        let size = PreviewLayout.contentSize(for: doc, diagnostic: "Map probe: OK 0.8s 1600×1040")
        XCTAssertEqual(size.width, PreviewLayout.width)
        XCTAssertGreaterThan(size.height, PreviewLayout.plotHeight)
        let ctx = Self.bitmap(size)
        PreviewLayout.draw(doc, diagnostic: "Map probe: OK 0.8s 1600×1040", in: ctx, size: size)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }

    func testPreviewLayoutWithoutDrawableDataStillRenders() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("trk-without-trkseg.gpx"), limits: .preview)
        let size = PreviewLayout.contentSize(for: doc, diagnostic: nil)
        let ctx = Self.bitmap(size)
        PreviewLayout.draw(doc, diagnostic: nil, in: ctx, size: size)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }

    func testErrorCardRenders() {
        let ctx = Self.bitmap(PreviewLayout.errorSize)
        PreviewLayout.drawError(GPXError.malformedXML(line: 12, column: 3), fileName: "x.gpx", in: ctx)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }
}
