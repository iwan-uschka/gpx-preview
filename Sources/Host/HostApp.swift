import MapKit
import SwiftUI

@main
struct GPXPreviewApp: App {
    var body: some Scene {
        Window("GPX Preview", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var probeText: String?
    @State private var probing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("GPX Preview is installed").font(.title2).bold()
            }

            Text("Select a .gpx file in Finder and press Space to preview it. Finder icons show "
                 + "the route shape as a thumbnail. If nothing appears, enable GPX Preview under "
                 + "System Settings → General → Login Items & Extensions → Quick Look.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Privacy") {
                Text("The Quick Look preview extension is allowed to contact Apple Maps to request "
                     + "map imagery for the area of the file being previewed. In this build it only "
                     + "runs a diagnostic map request and still draws the track without a map. "
                     + "The thumbnail extension has no network access at all; it only reads the "
                     + "file Finder hands it.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Checks whether this app can fetch an Apple Maps snapshot. Compare with the "
                         + "\"Map probe\" line in a Quick Look preview: if this works but the preview "
                         + "fails, the Quick Look sandbox is blocking MapKit.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Test map access") { runProbe() }
                            .disabled(probing)
                        if probing { ProgressView().controlSize(.small) }
                    }
                    if let probeText {
                        Text(probeText)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private func runProbe() {
        probing = true
        probeText = nil
        // A fixed, well-mapped area; the point is reachability, not the region.
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417),
                                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.15))
        Task {
            let result = await MapSnapshot.probe(region: region)
            var text = result.diagnosticLine
            switch result {
            case .success:
                text += "\nImage: \(MapSnapshot.diagnosticImageURL.path)"
            case let .failure(_, _, description):
                text += "\n\(description)"
            }
            await MainActor.run {
                probeText = text
                probing = false
            }
        }
    }
}
