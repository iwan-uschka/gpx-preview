import Foundation

/// Streaming GPX 1.0 / 1.1 parser on Foundation's `XMLParser`.
///
/// Memory stays bounded because the file is streamed and every growth path
/// (stored points, element count, text per element, wall-clock time) has a
/// ceiling from `GPXLimits`. Schema order is not enforced; unknown elements
/// and everything under `<extensions>` are ignored but still counted.
enum GPXParser {

    /// Parses a file, rejecting it by size before it is opened.
    static func parse(url: URL,
                      limits: GPXLimits,
                      now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) throws -> GPXDocument {
        let size: Int
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw GPXError.unreadable("not a regular file")
            }
            size = fileSize
        } catch let error as GPXError {
            throw error
        } catch {
            throw GPXError.unreadable(error.localizedDescription)
        }
        guard size <= limits.maxFileSize else { throw GPXError.limitExceeded(.fileSize) }
        guard size > 0 else { throw GPXError.notGPX }
        guard let stream = InputStream(url: url) else {
            throw GPXError.unreadable("could not open stream")
        }
        return try run(XMLParser(stream: stream), limits: limits, now: now,
                       fileName: url.lastPathComponent)
    }

    /// Parses in-memory data. No file-size check (the caller already holds
    /// the bytes); every other limit applies.
    static func parse(data: Data,
                      limits: GPXLimits,
                      fileName: String? = nil,
                      now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) throws -> GPXDocument {
        guard !data.isEmpty else { throw GPXError.notGPX }
        return try run(XMLParser(data: data), limits: limits, now: now, fileName: fileName)
    }

    private static func run(_ parser: XMLParser,
                            limits: GPXLimits,
                            now: @escaping () -> ContinuousClock.Instant,
                            fileName: String?) throws -> GPXDocument {
        let delegate = Delegate(limits: limits, now: now)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let ok = parser.parse()
        if let abort = delegate.abortReason { throw abort }
        if !ok || delegate.parseErrorSeen {
            throw GPXError.malformedXML(line: delegate.errorLine ?? parser.lineNumber,
                                        column: delegate.errorColumn ?? parser.columnNumber)
        }
        guard delegate.sawRoot else { throw GPXError.notGPX }
        var doc = delegate.doc
        doc.fileName = fileName
        return doc
    }

    // MARK: - Helpers (internal for tests)

    /// Splits a keywords string on commas and whitespace; trims, drops
    /// empties and duplicates, keeps first-seen order.
    static func splitKeywords(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        for piece in raw.components(separatedBy: separators) where !piece.isEmpty {
            if seen.insert(piece).inserted { out.append(piece) }
        }
        return out
    }

    /// Returns a coordinate only when it parses, is finite and in range.
    static func coordinate(lat: String?, lon: String?) -> (Double, Double)? {
        guard let latText = lat?.trimmingCharacters(in: .whitespaces),
              let lonText = lon?.trimmingCharacters(in: .whitespaces),
              let la = Double(latText), let lo = Double(lonText),
              la.isFinite, lo.isFinite,
              (-90.0...90.0).contains(la), (-180.0...180.0).contains(lo) else { return nil }
        return (la, lo)
    }

    // MARK: - Delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        let limits: GPXLimits
        let now: () -> ContinuousClock.Instant
        let startedAt: ContinuousClock.Instant

        var doc = GPXDocument()
        var sawRoot = false
        var abortReason: GPXError?
        var parseErrorSeen = false
        var errorLine: Int?
        var errorColumn: Int?

        private var stack: [String] = []
        /// One text buffer per open element, parallel to `stack`, so a stray
        /// child element cannot discard its parent's text.
        private var textStack: [(text: String, length: Int)] = []
        private var elementCount = 0
        private var storedPoints = 0

        private var pendingPoint: GPXPoint?
        private var pendingPointValid = false
        private var inTrack = false
        private var inSegment = false
        private var inRoute = false

        private let isoPlain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        private let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        init(limits: GPXLimits, now: @escaping () -> ContinuousClock.Instant) {
            self.limits = limits
            self.now = now
            self.startedAt = now()
        }

        private func abort(_ parser: XMLParser, _ reason: GPXError) {
            guard abortReason == nil else { return }
            abortReason = reason
            parser.abortParsing()
        }

        private func parseDate(_ s: String) -> Date? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return isoPlain.date(from: t) ?? isoFractional.date(from: t)
        }

        // MARK: Elements

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard abortReason == nil else { return }
            elementCount += 1
            if elementCount > limits.maxElements {
                abort(parser, .limitExceeded(.elements))
                return
            }
            if elementCount % GPXLimits.deadlineCheckInterval == 0,
               now() - startedAt > limits.deadline {
                abort(parser, .timedOut)
                return
            }

            if stack.isEmpty {
                guard name == "gpx" else {
                    abort(parser, .notGPX)
                    return
                }
                sawRoot = true
                doc.version = Self.version(attribute: attributes["version"], namespace: namespaceURI)
            }
            stack.append(name)
            textStack.append(("", 0))

            let depth = stack.count
            let parent = depth >= 2 ? stack[depth - 2] : ""
            switch (depth, name) {
            case (2, "trk"):
                inTrack = true
                doc.tracks.append(GPXTrack(name: nil, segments: []))
            case (3, "trkseg") where inTrack:
                inSegment = true
                doc.tracks[doc.tracks.count - 1].segments.append([])
            case (4, "trkpt") where inSegment,
                 (3, "rtept") where inRoute,
                 (2, "wpt"):
                beginPoint(attributes)
            case (2, "rte"):
                inRoute = true
                doc.routes.append(GPXRoute(name: nil, points: []))
            case (3, "link") where parent == "metadata":
                if doc.link == nil, let href = attributes["href"] { doc.link = href }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard abortReason == nil, let top = textStack.indices.last,
                  textStack[top].length < limits.maxTextPerElement else { return }
            let remaining = limits.maxTextPerElement - textStack[top].length
            let count = string.count
            if count <= remaining {
                textStack[top].text += string
                textStack[top].length += count
            } else {
                textStack[top].text += string.prefix(remaining)
                textStack[top].length = limits.maxTextPerElement
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard abortReason == nil, !stack.isEmpty else { return }
            let depth = stack.count
            let parent = depth >= 2 ? stack[depth - 2] : ""
            let value = textStack.removeLast().text

            switch (depth, name) {
            // GPX 1.1 metadata
            case (3, "name") where parent == "metadata": doc.name = value.trimmed
            case (3, "desc") where parent == "metadata": doc.desc = value.trimmed
            case (3, "keywords") where parent == "metadata": doc.keywords = GPXParser.splitKeywords(value)
            case (3, "time") where parent == "metadata": doc.time = parseDate(value)
            // GPX 1.0 top-level metadata
            case (2, "name"): doc.name = value.trimmed
            case (2, "desc"): doc.desc = value.trimmed
            case (2, "url"): if doc.link == nil { doc.link = value.trimmed }
            case (2, "keywords"): doc.keywords = GPXParser.splitKeywords(value)
            case (2, "time"): doc.time = parseDate(value)
            // Track / route names for the title fallback
            case (3, "name") where parent == "trk" && inTrack:
                doc.tracks[doc.tracks.count - 1].name = value.trimmed
            case (3, "name") where parent == "rte" && inRoute:
                doc.routes[doc.routes.count - 1].name = value.trimmed
            // Point children
            case (_, "ele") where pendingPoint != nil && Self.isPoint(parent, depth: depth - 1):
                pendingPoint?.ele = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            case (_, "time") where pendingPoint != nil && Self.isPoint(parent, depth: depth - 1):
                pendingPoint?.time = parseDate(value)
            // Point / container ends
            case (4, "trkpt") where inSegment: endPoint { doc.tracks[doc.tracks.count - 1].appendToLastSegment($0) }
            case (3, "rtept") where inRoute: endPoint { doc.routes[doc.routes.count - 1].points.append($0) }
            case (2, "wpt"): endPoint { doc.waypoints.append($0) }
            case (3, "trkseg"): inSegment = false
            case (2, "trk"): inTrack = false
            case (2, "rte"): inRoute = false
            default: break
            }
            stack.removeLast()
        }

        private static func isPoint(_ name: String, depth: Int) -> Bool {
            switch (depth, name) {
            case (4, "trkpt"), (3, "rtept"), (2, "wpt"): return true
            default: return false
            }
        }

        private func beginPoint(_ attributes: [String: String]) {
            if let (lat, lon) = GPXParser.coordinate(lat: attributes["lat"], lon: attributes["lon"]) {
                pendingPoint = GPXPoint(lat: lat, lon: lon)
                pendingPointValid = true
            } else {
                pendingPoint = nil
                pendingPointValid = false
                doc.invalidPointCount += 1
            }
        }

        private func endPoint(_ store: (GPXPoint) -> Void) {
            defer { pendingPoint = nil; pendingPointValid = false }
            guard pendingPointValid, let point = pendingPoint else { return }
            guard storedPoints < limits.maxStoredPoints else {
                doc.truncated = true
                return
            }
            storedPoints += 1
            store(point)
        }

        private static func version(attribute: String?, namespace: String?) -> GPXVersion {
            switch attribute?.trimmingCharacters(in: .whitespaces) {
            case "1.1": return .v1_1
            case "1.0": return .v1_0
            default: break
            }
            switch namespace {
            case "http://www.topografix.com/GPX/1/1": return .v1_1
            case "http://www.topografix.com/GPX/1/0": return .v1_0
            default: return .unknown
            }
        }

        // MARK: DTD / entities — GPX never needs them; refuse outright.

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            abort(parser, .entityDeclaration)
        }

        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                    publicID: String?, systemID: String?) {
            abort(parser, .entityDeclaration)
        }

        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            abort(parser, .entityDeclaration)
            return nil
        }

        // MARK: Errors

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            guard !parseErrorSeen else { return }
            parseErrorSeen = true
            errorLine = parser.lineNumber
            errorColumn = parser.columnNumber
        }
    }
}

private extension GPXTrack {
    mutating func appendToLastSegment(_ point: GPXPoint) {
        segments[segments.count - 1].append(point)
    }
}

private extension String {
    var trimmed: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
