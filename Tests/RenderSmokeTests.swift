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

    /// True when `p` is opaque and each channel is within `tolerance` of `color`'s sRGB components.
    private static func matches(_ p: (UInt8, UInt8, UInt8, UInt8), _ color: CGColor, tolerance: Int = 3) -> Bool {
        guard let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?
            .components, c.count >= 3 else { return false }
        let expected = c.prefix(3).map { Int(($0 * 255).rounded()) }
        let actual = [Int(p.0), Int(p.1), Int(p.2)]
        return p.3 == 255 && zip(expected, actual).allSatisfy { abs($0 - $1) <= tolerance }
    }

    // breaks-if: the endpoint-marker branch in TrackRenderer.draw is removed or its colors are swapped
    func testEndpointMarkersUseStartAndEndColors() {
        let ctx = Self.bitmap(CGSize(width: 64, height: 64))
        var doc = GPXDocument()
        doc.tracks = [GPXTrack(name: nil, segments: [[GPXPoint(lat: 0, lon: 0), GPXPoint(lat: 1, lon: 0)]])]
        TrackRenderer.draw(doc, in: ctx, rect: CGRect(x: 0, y: 0, width: 64, height: 64),
                           project: { CGPoint(x: 32, y: 10 + $0.lat * 44) }, style: .preview)
        XCTAssertTrue(Self.matches(Self.pixel(ctx, 32, 10), TrackRenderer.startColor), "start marker")
        XCTAssertTrue(Self.matches(Self.pixel(ctx, 32, 54), TrackRenderer.endColor), "end marker")
    }

    // breaks-if: the route branch in TrackRenderer.draw is removed, or the endpoint markers stop falling back to routes when there are no tracks
    func testRouteOnlyDocumentDrawsRouteAndEndpointMarkers() {
        let ctx = Self.bitmap(CGSize(width: 100, height: 20))
        var doc = GPXDocument()
        doc.routes = [GPXRoute(name: nil, points: [GPXPoint(lat: 0, lon: 0), GPXPoint(lat: 0, lon: 5)])]
        TrackRenderer.draw(doc, in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                           project: { CGPoint(x: 10 + $0.lon * 16, y: 10) }, style: .preview)
        XCTAssertGreaterThan(Self.pixel(ctx, 10, 10).3, 0)   // route start
        XCTAssertGreaterThan(Self.pixel(ctx, 90, 10).3, 0)   // route end
        XCTAssertTrue(Self.matches(Self.pixel(ctx, 10, 10), TrackRenderer.startColor), "route start marker")
        XCTAssertTrue(Self.matches(Self.pixel(ctx, 90, 10), TrackRenderer.endColor), "route end marker")
    }

    // breaks-if: the points.count == 1 special case in strokePolyline is removed
    func testSinglePointSegmentDrawsAMark() {
        let ctx = Self.bitmap(CGSize(width: 64, height: 64))
        var doc = GPXDocument()
        doc.tracks = [GPXTrack(name: nil, segments: [[GPXPoint(lat: 0, lon: 0)]])]
        TrackRenderer.draw(doc, in: ctx, rect: CGRect(x: 0, y: 0, width: 64, height: 64),
                           project: { _ in CGPoint(x: 32, y: 32) }, style: .preview)
        XCTAssertGreaterThan(Self.pixel(ctx, 32, 32).3, 0)
    }

    // breaks-if: the guard in drawScaleBar or its line-drawing is broken
    func testScaleBarDrawsWhenMetresPerPointPositive() {
        let ctx = Self.bitmap(CGSize(width: 100, height: 40))
        // 10 m/pt over 100 pt → 200 m bar, 20 pt long, baseline at y = 12 from x = 12.
        TrackRenderer.drawScaleBar(in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                                   metresPerPoint: 10, color: CGColor(gray: 0, alpha: 1))
        XCTAssertGreaterThan(Self.pixel(ctx, 20, 12).3, 0)
    }

    func testPreviewLayoutDrawsWithoutCrashing() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("full-1.1.gpx"), limits: .preview)
        let size = PreviewLayout.contentSize(for: doc)
        XCTAssertEqual(size.width, PreviewLayout.width)
        XCTAssertGreaterThan(size.height, PreviewLayout.plotHeight)
        let ctx = Self.bitmap(size)
        PreviewLayout.draw(doc, in: ctx, size: size)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }

    func testPreviewLayoutWithoutDrawableDataStillRenders() throws {
        let doc = try GPXParser.parse(url: GPXParserTests.fixture("trk-without-trkseg.gpx"), limits: .preview)
        let size = PreviewLayout.contentSize(for: doc)
        let ctx = Self.bitmap(size)
        PreviewLayout.draw(doc, in: ctx, size: size)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }

    func testErrorCardRenders() {
        let ctx = Self.bitmap(PreviewLayout.errorSize)
        PreviewLayout.drawError(GPXError.malformedXML(line: 12, column: 3), fileName: "x.gpx", in: ctx)
        XCTAssertTrue(Self.isWhite(Self.pixel(ctx, 2, 2)))
    }
}
