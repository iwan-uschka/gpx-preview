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
                Text("Neither extension has network access. Both only read the file Finder hands "
                     + "them and draw the track locally, without a map.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}
