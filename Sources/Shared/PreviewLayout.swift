import CoreGraphics
import CoreText
import Foundation

/// Page layout of the spacebar preview, drawn into a plain y-up `CGContext`
/// (Quick Look's vector reply context in production, a bitmap in tests):
/// title, vector plot, stats line, optional diagnostic line, keyword labels,
/// link, description.
enum PreviewLayout {
    static let width: CGFloat = 800
    static let margin: CGFloat = 24
    static let plotHeight: CGFloat = 480
    static let maxDescLines = 12

    static let textColor = CGColor(gray: 0.1, alpha: 1)
    static let secondaryColor = CGColor(gray: 0.45, alpha: 1)
    static let backgroundColor = CGColor(gray: 1, alpha: 1)
    static let plotBackground = CGColor(srgbRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)

    private static let titleFont = TextDrawing.font(size: 20, bold: true)
    private static let bodyFont = TextDrawing.font(size: 13)
    private static let smallFont = TextDrawing.font(size: 11)

    // MARK: - Text content (pure, tested)

    /// "1,234 points · 12.3 km · ↑ 456 m · 2 h 13 min", plus truncation and
    /// invalid-point notes when relevant.
    static func statsLine(_ doc: GPXDocument) -> String {
        let segments = doc.trackSegments + doc.routes.map(\.points)
        var parts = ["\(grouped(doc.pointCount)) point\(doc.pointCount == 1 ? "" : "s")"]
        let distance = Geo.distance(segments: segments)
        if distance > 0 { parts.append(TrackRenderer.formatDistance(distance)) }
        if let gain = Geo.elevationGain(segments: doc.trackSegments) {
            parts.append(String(format: "↑ %.0f m", gain))
        }
        if let span = Geo.timeSpan(segments: doc.trackSegments), span > 0 {
            parts.append(formatDuration(span))
        }
        parts.append(contentsOf: notes(doc))
        return parts.joined(separator: " · ")
    }

    /// "(truncated)" and "N invalid points skipped", when they apply.
    static func notes(_ doc: GPXDocument) -> [String] {
        var out: [String] = []
        if doc.truncated { out.append("(truncated)") }
        if doc.invalidPointCount > 0 {
            let n = doc.invalidPointCount
            out.append("\(grouped(n)) invalid point\(n == 1 ? "" : "s") skipped")
        }
        return out
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let days = total / 86_400, hours = (total % 86_400) / 3_600, minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(total) s"
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    // MARK: - Size + drawing

    private enum Block {
        case title(String)
        case plot
        case note(String)
        case line(String, CTFont, CGColor)
        case keywords([[String]])
        case gap(CGFloat)

        var height: CGFloat {
            switch self {
            case .title: return 30
            case .plot: return PreviewLayout.plotHeight
            case .note: return 18
            case .line(_, let font, _): return ceil(CTFontGetSize(font) * 1.45)
            case .keywords(let rows): return CGFloat(rows.count) * 22
            case .gap(let h): return h
            }
        }
    }

    private static let keywordFont = TextDrawing.font(size: 11)

    private static func blocks(_ doc: GPXDocument, diagnostic: String?) -> [Block] {
        let contentWidth = width - 2 * margin
        var b: [Block] = [.title(doc.title), .gap(8), .plot]
        let notes = notes(doc)
        b.append(notes.isEmpty ? .gap(8) : .note(notes.joined(separator: " · ")))
        b.append(.line(statsLine(doc), bodyFont, textColor))
        if let diagnostic { b.append(.line(diagnostic, smallFont, secondaryColor)) }
        if !doc.keywords.isEmpty {
            b.append(.gap(6))
            b.append(.keywords(keywordRows(doc.keywords, width: contentWidth)))
        }
        if let link = doc.link.nonBlank {
            b.append(.gap(4))
            b.append(.line(link, smallFont, CGColor(srgbRed: 0.1, green: 0.35, blue: 0.8, alpha: 1)))
        }
        if let desc = doc.desc.nonBlank {
            b.append(.gap(6))
            for l in TextDrawing.wrap(desc, width: contentWidth, font: bodyFont, maxLines: maxDescLines) {
                b.append(.line(l, bodyFont, textColor))
            }
        }
        b.append(.gap(margin))
        return b
    }

    private static func keywordRows(_ keywords: [String], width: CGFloat) -> [[String]] {
        var rows: [[String]] = [[]]
        var x: CGFloat = 0
        for k in keywords {
            let w = TextDrawing.width(k, font: keywordFont) + 16
            if x + w > width, !(rows.last?.isEmpty ?? true) { rows.append([]); x = 0 }
            rows[rows.count - 1].append(k)
            x += w + 6
        }
        return rows
    }

    static func contentSize(for doc: GPXDocument, diagnostic: String?) -> CGSize {
        let h = blocks(doc, diagnostic: diagnostic).reduce(margin) { $0 + $1.height }
        return CGSize(width: width, height: ceil(h))
    }

    /// Draws the full preview page. `size` must come from `contentSize`.
    static func draw(_ doc: GPXDocument, diagnostic: String?, in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(backgroundColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        var top = size.height - margin
        let x = margin
        let contentWidth = size.width - 2 * margin
        for block in blocks(doc, diagnostic: diagnostic) {
            let h = block.height
            let rect = CGRect(x: x, y: top - h, width: contentWidth, height: h)
            switch block {
            case .title(let t):
                TextDrawing.draw(t, at: CGPoint(x: x, y: rect.minY + 7), font: titleFont, color: textColor, in: ctx)
            case .plot:
                drawPlot(doc, in: ctx, rect: rect)
            case .note(let n):
                TextDrawing.draw(n, at: CGPoint(x: x, y: rect.minY + 4), font: smallFont,
                                 color: secondaryColor, in: ctx)
            case let .line(t, font, color):
                TextDrawing.draw(t, at: CGPoint(x: x, y: rect.minY + CTFontGetDescent(font) + 2),
                                 font: font, color: color, in: ctx)
            case .keywords(let rows):
                drawKeywords(rows, in: ctx, rect: rect)
            case .gap:
                break
            }
            top -= h
        }
    }

    private static func drawPlot(_ doc: GPXDocument, in ctx: CGContext, rect: CGRect) {
        let border = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(border)
        ctx.setFillColor(plotBackground)
        ctx.fillPath()
        ctx.addPath(border)
        ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
        ctx.setLineWidth(1)
        ctx.strokePath()

        guard let box = BoundingBox(points: doc.allPoints) else {
            let msg = "No track data"
            let font = TextDrawing.font(size: 15)
            TextDrawing.draw(msg, at: CGPoint(x: rect.midX - TextDrawing.width(msg, font: font) / 2, y: rect.midY),
                             font: font, color: secondaryColor, in: ctx)
            return
        }
        let projection = Projection.fit(box, into: rect)
        TrackRenderer.draw(doc, in: ctx, rect: rect, project: projection.project, style: .preview)
        TrackRenderer.drawScaleBar(in: ctx, rect: rect, metresPerPoint: projection.metresPerPoint,
                                   color: secondaryColor)
    }

    private static func drawKeywords(_ rows: [[String]], in ctx: CGContext, rect: CGRect) {
        var y = rect.maxY - 20
        for row in rows {
            var x = rect.minX
            for k in row {
                let w = TextDrawing.width(k, font: keywordFont) + 16
                let pill = CGRect(x: x, y: y, width: w, height: 18)
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
                ctx.fillPath()
                TextDrawing.draw(k, at: CGPoint(x: x + 8, y: y + 5), font: keywordFont,
                                 color: textColor, in: ctx)
                x += w + 6
            }
            y -= 22
        }
    }

    // MARK: - Error card

    static let errorSize = CGSize(width: 600, height: 160)

    static func errorText(_ error: Error) -> String {
        let reason = (error as? GPXError)?.message ?? error.localizedDescription
        return "Couldn't read GPX: \(reason)"
    }

    static func drawError(_ error: Error, fileName: String, in ctx: CGContext, size: CGSize = errorSize) {
        ctx.setFillColor(backgroundColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        TextDrawing.draw(fileName, at: CGPoint(x: margin, y: size.height - margin - 20),
                         font: titleFont, color: textColor, in: ctx)
        for (i, line) in TextDrawing.wrap(errorText(error), width: size.width - 2 * margin,
                                          font: bodyFont, maxLines: 4).enumerated() {
            TextDrawing.draw(line, at: CGPoint(x: margin, y: size.height - margin - 56 - CGFloat(i) * 19),
                             font: bodyFont, color: secondaryColor, in: ctx)
        }
    }
}
