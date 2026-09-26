import Foundation

/// Resource ceilings for one parse. Quick Look runs extensions with tight
/// memory and time budgets, so an oversized or hostile file must fail fast
/// rather than get the extension killed.
struct GPXLimits: Equatable {
    /// Checked from the file's size before it is opened.
    var maxFileSize: Int
    /// Beyond this many stored points, further points are dropped and the
    /// document is marked `truncated`.
    var maxStoredPoints: Int
    /// Beyond this many start-element callbacks, parsing aborts.
    var maxElements: Int
    /// Wall-clock budget, checked every `deadlineCheckInterval` elements.
    var deadline: Duration
    /// Characters kept per element; the rest are dropped silently.
    var maxTextPerElement: Int

    static let deadlineCheckInterval = 1_024

    static let preview = GPXLimits(maxFileSize: 64 << 20,
                                   maxStoredPoints: 1_000_000,
                                   maxElements: 5_000_000,
                                   deadline: .seconds(4),
                                   maxTextPerElement: 64 << 10)

    static let thumbnail = GPXLimits(maxFileSize: 16 << 20,
                                     maxStoredPoints: 200_000,
                                     maxElements: 1_000_000,
                                     deadline: .milliseconds(1_500),
                                     maxTextPerElement: 64 << 10)
}

enum GPXLimitKind: Equatable {
    case fileSize
    case elements
}

enum GPXError: Error, Equatable {
    case malformedXML(line: Int, column: Int)
    case notGPX
    /// Parsed fine but holds no drawable point. The preview still renders the
    /// metadata; only the thumbnail treats this as a failure.
    case noDrawableData
    case limitExceeded(GPXLimitKind)
    case timedOut
    /// The file declares a DTD entity. GPX never needs one, and entity
    /// expansion is the billion-laughs / XXE attack surface.
    case entityDeclaration
    /// The file couldn't be opened or measured.
    case unreadable(String)

    /// One-line text for the preview's error card.
    var message: String {
        switch self {
        case let .malformedXML(line, column):
            return "malformed XML at line \(line), column \(column)"
        case .notGPX:
            return "not a GPX file"
        case .noDrawableData:
            return "no track data"
        case .limitExceeded(.fileSize):
            return "file is too large"
        case .limitExceeded(.elements):
            return "file has too many XML elements"
        case .timedOut:
            return "parsing took too long"
        case .entityDeclaration:
            return "file declares XML entities, which GPX never uses"
        case let .unreadable(reason):
            return "file could not be read (\(reason))"
        }
    }
}
