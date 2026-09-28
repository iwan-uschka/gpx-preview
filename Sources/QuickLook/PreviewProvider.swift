import Foundation
import os
import QuickLookUI

/// Data-based Quick Look preview: parses the GPX and replies with a vector
/// (PDF) drawing of `PreviewLayout`.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    private static let log = Logger(subsystem: "io.github.iwan-uschka.GPXPreview", category: "preview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let doc: GPXDocument
        do {
            doc = try GPXParser.parse(url: url, limits: .preview)
        } catch {
            Self.log.error("parse failed: \(PreviewLayout.errorText(error), privacy: .public)")
            let name = url.lastPathComponent
            return QLPreviewReply(contextSize: PreviewLayout.errorSize, isBitmap: false) { ctx, _ in
                PreviewLayout.drawError(error, fileName: name, in: ctx)
            }
        }

        let size = PreviewLayout.contentSize(for: doc)
        let reply = QLPreviewReply(contextSize: size, isBitmap: false) { ctx, _ in
            PreviewLayout.draw(doc, in: ctx, size: size)
        }
        reply.title = doc.title
        return reply
    }
}
