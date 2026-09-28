# Changelog

## [0.1.0] - 2026-09-28

### Added

- GPX Quick Look preview and thumbnail extensions with vector-only rendering and no network access.

### Removed

- The MapKit feasibility probe and its "Test map access" button in the host app. The probe checked whether the preview extension could fetch Apple Maps imagery for a map basemap. It could not: the host app's identical `MKMapSnapshotter` call returned a full map, while the sandboxed extension got only MapKit's empty placeholder grid, with no error. MapKit, the probe code and every `network.client` entitlement are gone; both extensions stay vector-only.
- The temporary network-reachability probe (`NetworkProbe.swift`) and the `network.client` entitlement it briefly brought back to the preview extension. It followed up on the MapKit result. A plain HTTPS GET to an OpenStreetMap tile hostname failed with a DNS-resolution error (`NSURLErrorCannotFindHost`, -1003). A GET to a loopback IP literal, with no DNS involved, also failed, with `EPERM` at the `connect()` syscall. So the sandbox blocks the outbound socket connection itself, not just DNS. That rules out any local-proxy or local-webserver workaround, such as a localhost tile-caching proxy, for reaching live map tiles from inside this extension.

### Fixed

- The Quick Look preview crashed on every spacebar press on macOS 26, inside PlugInKit's extension bootstrap before any of its code ran. Cause: the space in the host app's bundle folder name (`GPX Preview.app`). The product now installs as `GPXPreview.app`; the display name stays "GPX Preview". The data-based `QLPreviewProvider` API and the `NSViewController`-based API crashed identically, so the API choice was not a factor.
- The build's network-entitlement guard checked only the thumbnail extension; it now also covers the Quick Look extension and the host app, closing the gap that let the reverted `NetworkProbe.swift` entitlement through undetected.
- Reinstalling over an existing copy never unregistered the old PluginKit/LaunchServices entries before deleting the bundle, unlike `uninstall.sh`; `install.sh` now unregisters first.
- The GPX parser's text accumulator was reset by any child element start/end, silently dropping already-accumulated text when malformed XML nested an unexpected element inside a text-bearing field.
- The preview's stats line computed distance over both tracks and routes but elevation gain and duration only over tracks, so a route-only GPX file with elevation/time data showed distance but silently omitted the other two.

### Documentation

- Noted that `install.sh`/`uninstall.sh` need admin-group rights on `/Applications`, and that managed Macs may need an org-provided privilege-elevation tool first.
- Corrected two stale cross-references (a README heading renamed since a doc comment quoted it; a "described above" reference in TESTING.md that pointed at nothing) and clarified that the host app's install guidance must name both extensions, not just Quick Look.
