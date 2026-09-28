# Changelog

## [Unreleased]

### Added

- GPX Quick Look preview and thumbnail extensions with vector-only rendering and no network access.

### Removed

- The MapKit feasibility probe and its "Test map access" button in the host app. The probe checked whether the preview extension could fetch Apple Maps imagery for a map basemap. It could not: the host app's identical `MKMapSnapshotter` call returned a full map, while the sandboxed extension got only MapKit's empty placeholder grid, with no error. MapKit, the probe code and every `network.client` entitlement are gone; both extensions stay vector-only.
- The temporary network-reachability probe (`NetworkProbe.swift`) and the `network.client` entitlement it briefly brought back to the preview extension. It followed up on the MapKit result. A plain HTTPS GET to an OpenStreetMap tile hostname failed with a DNS-resolution error (`NSURLErrorCannotFindHost`, -1003). A GET to a loopback IP literal, with no DNS involved, also failed, with `EPERM` at the `connect()` syscall. So the sandbox blocks the outbound socket connection itself, not just DNS. That rules out any local-proxy or local-webserver workaround, such as a localhost tile-caching proxy, for reaching live map tiles from inside this extension.

### Fixed

- The Quick Look preview crashed on every spacebar press on macOS 26, inside PlugInKit's extension bootstrap before any of its code ran. Cause: the space in the host app's bundle folder name (`GPX Preview.app`). The product now installs as `GPXPreview.app`; the display name stays "GPX Preview". The data-based `QLPreviewProvider` API and the `NSViewController`-based API crashed identically, so the API choice was not a factor.

### Documentation

- Noted that `install.sh`/`uninstall.sh` need admin-group rights on `/Applications`, and that managed Macs may need an org-provided privilege-elevation tool first.
