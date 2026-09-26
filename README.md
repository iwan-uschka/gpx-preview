# GPX Preview

Quick Look preview and Finder thumbnails for `.gpx` files on current macOS.

The old `.qlgenerator` plugins no longer load on macOS 15 and later, and there
is no modern `.appex` GPX previewer. This project tests whether sandboxed app
extensions can fill that gap:

- a **Preview Extension** (spacebar preview) that draws the track as a vector
  line plot with the key metadata. A later stage may put the track on an Apple
  Maps basemap; this build only runs a *diagnostic* map request (see Status).
- a **Thumbnail Extension** that draws the track shape for Finder icons,
  entirely locally, with no network access.

No third-party dependencies, no third-party map provider.

## Status

Stage 1 (scaffold, vector preview and thumbnail, MapKit feasibility probe) is
built and unit-tested. The go/no-go verification (stage 2) has not been run
yet.

## Install

Requirements: macOS 14 or later, Xcode, and `xcodegen` (`brew install xcodegen`).

```sh
bash scripts/build.sh        # generates the Xcode project, builds, ad-hoc signs
bash scripts/install.sh      # copies to /Applications and registers the extensions
```

Uninstall with `bash scripts/uninstall.sh`. If Finder keeps showing old `.gpx`
icons, run `bash scripts/refresh-thumbnails.sh`.

### Gatekeeper: "Open Anyway"

The app is ad-hoc signed: no paid Apple developer account, no notarization.
That is a deliberate trade-off. The first time you open it, macOS may refuse
with an "unidentified developer" warning. Open **System Settings → Privacy &
Security**, scroll to the message about "GPX Preview" and click **Open
Anyway**. This is needed once.

If previews still don't appear, check that both extensions are switched on
under **System Settings → General → Login Items & Extensions → Quick Look**.

## Privacy

- **Preview extension.** It holds the `network.client` entitlement so it can ask
  Apple Maps for map imagery of the area shown in the file. That is not wired
  up in this build: the preview is still vector-only. The only request it makes
  is a diagnostic map snapshot for the file's bounding box, whose outcome shows
  up as one "Map probe" line in the preview (see Status). No file contents
  leave your Mac; the request carries only a map region.
- **Thumbnail extension.** No network entitlement, now or later. It reads the
  file Finder hands it and draws locally, nothing else. `scripts/build.sh`
  fails the build if that extension ever gains a network entitlement.
- **Host app.** Its network entitlement exists only for the "Test map access"
  button, which runs the same diagnostic request on demand.

### Why the thumbnail never uses a map

Finder requests thumbnails in bulk and caches them on disk. Apple's MapKit
terms forbid bulk downloading and caching of map data, and Apple's map
attribution cannot stay legible at 32–256 px icon sizes. So the thumbnail is
the vector track shape, permanently.

## How it works

- `.gpx` has no Apple `public.*` type. The de-facto identifier is
  `com.topografix.gpx`, from the format owner's namespace. The host app
  **imports** (does not export) that type, so `.gpx` resolves to it even when no
  other GPX app is installed. Both extensions claim exactly
  `com.topografix.gpx`, never `public.xml`, which would take over every XML
  file.
- Parsing uses Foundation's streaming `XMLParser` with hard limits (file size,
  stored points, element count, text per element, wall-clock deadline) so a huge
  or hostile file fails fast. DTD entity declarations abort parsing, which
  blocks billion-laughs and XXE inputs.
- The vector plot is a local equirectangular projection fitted to the track's
  bounding box (8% padding, aspect ratio preserved), one polyline per track
  segment, dashed routes, waypoint dots, green/red start/end markers and a scale
  bar.

## Manual verification checklist

Unit tests (`xcodebuild test -scheme GPXPreview`) cover the parser, limits,
geometry and rendering. The following needs a real install:

- [ ] `pluginkit -mAvvv -p com.apple.quicklook.preview | grep -A3 GPX` lists the preview extension
- [ ] `pluginkit -mAvvv -p com.apple.quicklook.thumbnail | grep -A3 GPX` lists the thumbnail extension
- [ ] `swift -e 'import UniformTypeIdentifiers; print(UTType(filenameExtension:"gpx")!.identifier)'` prints `com.topografix.gpx`
- [ ] `mdls -name kMDItemContentType Tests/Fixtures/full-1.1.gpx` shows `com.topografix.gpx`
- [ ] `lsregister -dump | grep -A12 com.topografix.gpx` shows the GPX Preview import
- [ ] `qlmanage -p Tests/Fixtures/full-1.1.gpx` shows the track plot, not XML text
- [ ] `qlmanage -t -s 512 -o /tmp/qlout Tests/Fixtures/full-1.1.gpx` writes a route thumbnail
- [ ] Finder: spacebar on a `.gpx` shows the preview; icon and column view show the route thumbnail
- [ ] System Settings → General → Login Items & Extensions → Quick Look lists both extensions, enabled
- [ ] First launch: Gatekeeper "Open Anyway" works as described above

`lsregister` lives at
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`.

## Legal

- MIT licensed, see [LICENSE](LICENSE).
- GPX is an open format published by TopoGrafix. This project imports the
  `com.topografix.gpx` type identifier for interoperability and claims no
  ownership of it.
- XML parsing uses Foundation's `XMLParser`, part of macOS; nothing is bundled.
- No restricted entitlements: ad-hoc-signed code that claims one (for example
  `com.apple.developer.maps`) is killed at launch.
