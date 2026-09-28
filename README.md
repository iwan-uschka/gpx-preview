# GPX Preview

Quick Look preview for `.gpx` files on current macOS.

The old `.qlgenerator` plugins no longer load on macOS 15 and later, and there
is no modern `.appex` GPX previewer. This project fills that gap with a
sandboxed **Preview Extension** (spacebar preview) that draws the track as a
vector line plot with the key metadata, entirely locally, with no network
access.

No third-party dependencies, no map basemap of any kind.

## Install

Requirements: macOS 14 or later, Xcode, and `xcodegen` (`brew install xcodegen`).

```sh
bash scripts/build.sh        # generates the Xcode project, builds, ad-hoc signs
bash scripts/install.sh      # copies to /Applications and registers the extensions
```

Uninstall with `bash scripts/uninstall.sh`.

`install.sh`/`uninstall.sh` write to `/Applications`, which requires
admin-group membership. On an organization-managed Mac your account may be a
Standard account with no local admin password to enter — in that case, use
whatever privilege-elevation tool your organization's device management
provides to request temporary admin rights first, then run the script
normally.

### Gatekeeper: "Open Anyway"

The app is ad-hoc signed: no paid Apple developer account, no notarization.
That is a deliberate trade-off. The first time you open it, macOS may refuse
with an "unidentified developer" warning. Open **System Settings → Privacy &
Security**, scroll to the message about "GPX Preview" and click **Open
Anyway**. This is needed once.

If previews still don't appear, check that both extensions are switched on
under **System Settings → General → Login Items & Extensions → Quick Look**.

## Privacy

- **Preview extension.** No network entitlement. It reads the file Quick Look
  hands it and draws locally, nothing else.
- **Host app.** No network entitlement. It only shows install guidance.

`scripts/build.sh` fails the build if any bundle ever gains a network
entitlement.

### Why the preview doesn't use a map

The sandbox blocks the extension's network access entirely: MapKit returns
only an empty placeholder grid, and plain connections fail at the
`connect()` syscall, even to a loopback address. See
[CHANGELOG.md](CHANGELOG.md) for how this was established.

### Why Finder thumbnails don't appear

The Thumbnail extension builds, signs, and registers correctly, but macOS
never calls it: `.gpx` conforms to `public.xml` → `public.text`, and Quick
Look's Thumbnail pipeline has a built-in generator that takes priority over
any third-party extension for `public.text`-conforming types (confirmed via
Console: `ThumbnailsAgent ... reason: internal generator preferred`).
Dropping the XML conformance would silence it, at the cost of `.gpx` no
longer being recognized as XML anywhere — not a trade worth making. Quick
Look preview (spacebar) is unaffected.

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
- The preview extension uses the data-based Quick Look API: a
  `QLPreviewProvider` parses the file in `providePreview(for:)` and replies with
  a vector (non-bitmap) `QLPreviewReply` that draws the page. A file that fails
  to parse gets an error card in the same kind of reply, not Quick Look's
  generic fallback.
- The vector plot is a local equirectangular projection fitted to the track's
  bounding box (8% padding, aspect ratio preserved), one polyline per track
  segment, dashed routes, waypoint dots, green/red start/end markers and a scale
  bar.

## Legal

- MIT licensed, see [LICENSE](LICENSE).
- GPX is an open format published by TopoGrafix. This project imports the
  `com.topografix.gpx` type identifier for interoperability and claims no
  ownership of it.
- XML parsing uses Foundation's `XMLParser`, part of macOS; nothing is bundled.
- No restricted entitlements: ad-hoc-signed code that claims one (for example
  `com.apple.developer.maps`) is killed at launch.
