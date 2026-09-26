import CoreGraphics
import CoreText
import Foundation

/// Stroking core shared by preview and thumbnail. It only knows how to draw
/// a document through a projection closure, so tests can feed it a fake
/// projection and the vector path feeds it `Projection.fit(...)`.
enum TrackRenderer {

    struct Style {
        var trackColor: CGColor
        var routeColor: CGColor
        var waypointColor: CGColor
        var lineWidth: CGFloat
        var routeDash: [CGFloat]
        var waypointRadius: CGFloat
        /// 0 hides the start/end markers (tiny thumbnails).
        var endpointRadius: CGFloat

        static let preview = Style(trackColor: CGColor(srgbRed: 0.85, green: 0.20, blue: 0.10, alpha: 1),
                                   routeColor: CGColor(srgbRed: 0.10, green: 0.35, blue: 0.85, alpha: 1),
                                   waypointColor: CGColor(srgbRed: 0.30, green: 0.30, blue: 0.30, alpha: 1),
                                   lineWidth: 2.5, routeDash: [6, 4],
                                   waypointRadius: 3, endpointRadius: 5)

        /// Line weights scaled for a square thumbnail of `side` pixels.
        static func thumbnail(side: CGFloat) -> Style {
            var s = preview
            s.lineWidth = max(1, side / 64)
            s.routeDash = [side / 24, side / 40]
            s.waypointRadius = max(1, side / 96)
            s.endpointRadius = side >= 128 ? side / 48 : 0
            return s
        }
    }

    static let startColor = CGColor(srgbRed: 0.15, green: 0.65, blue: 0.25, alpha: 1)
    static let endColor = CGColor(srgbRed: 0.85, green: 0.10, blue: 0.10, alpha: 1)

    /// Draws tracks (one polyline per segment), dashed routes, waypoint dots
    /// and start/end markers, clipped to `rect`.
    static func draw(_ doc: GPXDocument, in ctx: CGContext, rect: CGRect,
                     project: (GPXPoint) -> CGPoint, style: Style) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: rect)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.setLineWidth(style.lineWidth)

        // Routes first so a track drawn over the same way stays on top.
        ctx.setStrokeColor(style.routeColor)
        ctx.setLineDash(phase: 0, lengths: style.routeDash)
        for route in doc.routes { strokePolyline(route.points, width: style.lineWidth, ctx: ctx, project: project) }
        ctx.setLineDash(phase: 0, lengths: [])

        ctx.setStrokeColor(style.trackColor)
        for seg in doc.trackSegments { strokePolyline(seg, width: style.lineWidth, ctx: ctx, project: project) }

        ctx.setFillColor(style.waypointColor)
        for wpt in doc.waypoints { fillDot(project(wpt), radius: style.waypointRadius, ctx: ctx) }

        if style.endpointRadius > 0 {
            let line = doc.trackSegments.flatMap { $0 }
            let path = line.isEmpty ? doc.routes.flatMap(\.points) : line
            if let first = path.first, let last = path.last, path.count > 1 {
                ctx.setFillColor(startColor)
                fillDot(project(first), radius: style.endpointRadius, ctx: ctx)
                ctx.setFillColor(endColor)
                fillDot(project(last), radius: style.endpointRadius, ctx: ctx)
            }
        }
    }

    private static func strokePolyline(_ points: [GPXPoint], width: CGFloat, ctx: CGContext, project: (GPXPoint) -> CGPoint) {
        guard let first = points.first else { return }
        if points.count == 1 {
            // A one-point segment still deserves a mark.
            fillDot(project(first), radius: width, ctx: ctx, useStroke: true)
            return
        }
        ctx.beginPath()
        ctx.move(to: project(first))
        for p in points.dropFirst() { ctx.addLine(to: project(p)) }
        ctx.strokePath()
    }

    private static func fillDot(_ c: CGPoint, radius: CGFloat, ctx: CGContext, useStroke: Bool = false) {
        let r = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        if useStroke {
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeEllipse(in: r.insetBy(dx: radius / 2, dy: radius / 2))
            ctx.restoreGState()
        } else {
            ctx.fillEllipse(in: r)
        }
    }

    // MARK: - Scale bar

    /// Largest 1/2/5 × 10ⁿ metre length not exceeding `maxMetres`.
    static func niceLength(maxMetres: Double) -> Double {
        guard maxMetres.isFinite, maxMetres > 0 else { return 0 }
        let exponent = floor(log10(maxMetres))
        let base = pow(10, exponent)
        for m in [5.0, 2.0, 1.0] where m * base <= maxMetres { return m * base }
        return base
    }

    static func formatDistance(_ metres: Double) -> String {
        if metres >= 1_000 {
            let km = metres / 1_000
            return km >= 10 || km == km.rounded() ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        return String(format: "%.0f m", metres)
    }

    /// Scale bar anchored at the bottom-left of `rect` (y-up coordinates),
    /// at most a quarter of the plot wide.
    static func drawScaleBar(in ctx: CGContext, rect: CGRect, metresPerPoint: Double, color: CGColor) {
        let metres = niceLength(maxMetres: metresPerPoint * Double(rect.width) / 4)
        guard metres > 0 else { return }
        let length = CGFloat(metres / metresPerPoint)
        let x = rect.minX + 12, y = rect.minY + 12
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x, y: y + 4))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + length, y: y))
        ctx.addLine(to: CGPoint(x: x + length, y: y + 4))
        ctx.strokePath()
        ctx.restoreGState()
        TextDrawing.draw(formatDistance(metres), at: CGPoint(x: x + length + 6, y: y - 3),
                         font: TextDrawing.font(size: 10), color: color, in: ctx)
    }

    // MARK: - Thumbnail

    /// The thumbnail image: the vector plot on a white rounded card, no text.
    /// Returns false when there is nothing to draw.
    @discardableResult
    static func drawThumbnail(_ doc: GPXDocument, size: CGSize, in ctx: CGContext) -> Bool {
        guard let box = BoundingBox(points: doc.allPoints) else { return false }
        let side = min(size.width, size.height)
        let card = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            .insetBy(dx: side * 0.04, dy: side * 0.04)
        let radius = card.width * 0.12
        let path = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
        ctx.setLineWidth(max(0.5, side / 256))
        ctx.strokePath()
        ctx.restoreGState()

        let projection = Projection.fit(box, into: card, padding: 0.12)
        draw(doc, in: ctx, rect: card, project: projection.project, style: .thumbnail(side: side))
        return true
    }
}

/// Minimal Core Text helpers so layout code stays AppKit-free.
enum TextDrawing {
    static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        return base ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func attributed(_ s: String, font: CTFont, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
    }

    /// Single line with its baseline at `point`.
    static func draw(_ s: String, at point: CGPoint, font: CTFont, color: CGColor, in ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed(s, font: font, color: color))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func width(_ s: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(s, font: font, color: CGColor(gray: 0, alpha: 1)))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Wraps `s` to `width`, returning at most `maxLines` lines (the last one
    /// ellipsised if text was cut).
    static func wrap(_ s: String, width: CGFloat, font: CTFont, maxLines: Int) -> [String] {
        var out: [String] = []
        let paragraphs = s.components(separatedBy: .newlines)
        var cut = false
        outer: for para in paragraphs {
            if para.isEmpty {
                if out.count >= maxLines { cut = true; break }
                out.append("")
                continue
            }
            let attr = attributed(para, font: font, color: CGColor(gray: 0, alpha: 1))
            let typesetter = CTTypesetterCreateWithAttributedString(attr)
            let ns = para as NSString
            var start = 0
            while start < ns.length {
                if out.count >= maxLines { cut = true; break outer }
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                guard count > 0 else { break }
                out.append(ns.substring(with: NSRange(location: start, length: count))
                    .trimmingCharacters(in: .whitespaces))
                start += count
            }
        }
        if cut, let last = out.last {
            out[out.count - 1] = last + " …"
        }
        return out
    }
}
