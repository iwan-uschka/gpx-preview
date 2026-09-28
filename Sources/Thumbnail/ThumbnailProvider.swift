import Foundation
import os
import QuickLookThumbnailing

/// Finder / Spotlight thumbnail: the track shape on a white card, drawn from
/// the local vector path only. This extension has no network entitlement by
/// design. (In practice Finder never calls it at all — see README, "Why
/// Finder thumbnails don't appear".)
final class ThumbnailProvider: QLThumbnailProvider {

    private static let log = Logger(subsystem: "io.github.iwan-uschka.GPXPreview", category: "thumbnail")

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let doc: GPXDocument
        do {
            doc = try GPXParser.parse(url: request.fileURL, limits: .thumbnail)
            guard doc.hasDrawableData else { throw GPXError.noDrawableData }
        } catch {
            // Returning the error makes Finder keep the generic icon.
            Self.log.error("thumbnail failed: \(PreviewLayout.errorText(error), privacy: .public)")
            handler(nil, error)
            return
        }

        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size) { ctx in
            TrackRenderer.drawThumbnail(doc, size: size, in: ctx)
        }
        reply.extensionBadge = "GPX"
        handler(reply, nil)
    }
}
