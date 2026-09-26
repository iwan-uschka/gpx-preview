import CoreGraphics

/// Pixel heuristics for the map-probe diagnostic. Lives in Shared (not next to
/// the MapKit code) so it can be unit-tested without MapKit or a network.
enum ImageStats {
    /// True when the image is (near-)uniform — what a snapshot looks like when
    /// tiles were refused and only the empty grey/beige base got drawn.
    /// Downsamples to 32×32 and compares per-channel range against `tolerance`
    /// (0…255).
    static func isBlank(_ image: CGImage, tolerance: Int = 12) -> Bool {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        var lo = [255, 255, 255], hi = [0, 0, 0]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for c in 0..<3 {
                let v = Int(pixels[i + c])
                lo[c] = min(lo[c], v); hi[c] = max(hi[c], v)
            }
        }
        return (0..<3).allSatisfy { hi[$0] - lo[$0] <= tolerance }
    }
}
