import AppKit
import MapKit
import os

/// Stage-1 feasibility probe: can MKMapSnapshotter deliver a real map image
/// from inside the ad-hoc-signed, sandboxed extension? The result only feeds a
/// diagnostic text line — no map is drawn in the preview yet.
///
/// Compiled into both the Quick Look extension and the host app (the host's
/// "Test map access" button), so the two can be compared: host OK but
/// extension failing points at the Quick Look sandbox; both failing with an
/// authorization error points at signing.
enum MapSnapshot {

    enum ProbeResult: Equatable {
        case success(duration: TimeInterval, pixelSize: CGSize, blank: Bool)
        case failure(errorDomain: String, code: Int, description: String)

        /// "Map probe: OK 0.8s 1600×1040" / "Map probe: failed <domain> <code>".
        var diagnosticLine: String {
            switch self {
            case let .success(duration, size, blank):
                return String(format: "Map probe: %@ %.1fs %d×%d", blank ? "BLANK" : "OK",
                              duration, Int(size.width), Int(size.height))
            case let .failure(domain, code, _):
                return "Map probe: failed \(domain) \(code)"
            }
        }
    }

    static let timeoutDomain = "GPXPreview.MapProbe"
    static let timeoutCode = 1
    static let defaultSize = CGSize(width: 800, height: 520)

    private static let log = Logger(subsystem: "io.github.iwan-uschka.GPXPreview", category: "map-probe")

    /// Rough region for a bounding box: centre plus 1.3× the span, with a
    /// minimum span so single-point files still get a sensible zoom. No
    /// antimeridian handling — good enough for a probe, not for the real
    /// renderer.
    static func region(for box: BoundingBox) -> MKCoordinateRegion {
        let lon = box.centerLon > 180 ? box.centerLon - 360 : box.centerLon
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(0.01, box.latSpan * 1.3)),
                                    longitudeDelta: min(350, max(0.01, box.lonSpan * 1.3)))
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: box.centerLat, longitude: lon),
                                  span: span)
    }

    /// Runs one snapshot, racing it against `timeout`. Never throws; every
    /// outcome is a `ProbeResult`.
    static func probe(region: MKCoordinateRegion, size: CGSize = defaultSize,
                      timeout: Duration = .seconds(5)) async -> ProbeResult {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard
        let snapshotter = MKMapSnapshotter(options: options)
        let started = ContinuousClock.now
        let once = ResumeOnce()

        let result: ProbeResult = await withCheckedContinuation { continuation in
            once.install(continuation)
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, error in
                let elapsed = ContinuousClock.now - started
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                if let error {
                    let ns = error as NSError
                    once.resume(.failure(errorDomain: ns.domain, code: ns.code, description: ns.localizedDescription))
                    return
                }
                guard let image = snapshot?.image,
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    once.resume(.failure(errorDomain: timeoutDomain, code: 2, description: "no image in snapshot"))
                    return
                }
                saveDiagnosticImage(cg)
                once.resume(.success(duration: seconds, pixelSize: CGSize(width: cg.width, height: cg.height),
                                     blank: ImageStats.isBlank(cg)))
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.resume(.failure(errorDomain: timeoutDomain, code: timeoutCode,
                                        description: "timed out after \(timeout)")) {
                    snapshotter.cancel()
                }
            }
        }

        switch result {
        case .success:
            log.notice("\(result.diagnosticLine, privacy: .public)")
        case let .failure(_, _, description):
            log.error("\(result.diagnosticLine, privacy: .public): \(description, privacy: .public)")
        }
        return result
    }

    /// Where the last probe image is written.
    static var diagnosticImageURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("map-probe.png")
    }

    // TEMPORARY (stage-1 diagnostic only): writes the raw snapshot so Apple's
    // built-in attribution can be inspected by hand. Remove together with the
    // probe once the real map renderer replaces it.
    private static func saveDiagnosticImage(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: diagnosticImageURL, options: .atomic)
            log.notice("probe image saved to \(diagnosticImageURL.path, privacy: .public)")
        } catch {
            log.error("could not save probe image: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Resumes a continuation exactly once, whichever of snapshot completion or
/// timeout gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MapSnapshot.ProbeResult, Never>?

    func install(_ c: CheckedContinuation<MapSnapshot.ProbeResult, Never>) {
        lock.lock(); continuation = c; lock.unlock()
    }

    /// Returns true if this call did the resuming.
    @discardableResult
    func resume(_ value: MapSnapshot.ProbeResult) -> Bool {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        guard let c else { return false }
        c.resume(returning: value)
        return true
    }
}
