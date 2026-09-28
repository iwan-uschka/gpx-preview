# Manual verification checklist

Unit tests (`xcodebuild test -scheme GPXPreview`) cover the parser, limits,
geometry and rendering. The following needs a real install:

- [ ] `pluginkit -mAvvv -p com.apple.quicklook.preview | grep -A3 GPX` lists the preview extension
- [ ] `pluginkit -mAvvv -p com.apple.quicklook.thumbnail | grep -A3 GPX` lists the thumbnail extension
- [ ] `swift -e 'import UniformTypeIdentifiers; print(UTType(filenameExtension:"gpx")!.identifier)'` prints `com.topografix.gpx`
- [ ] `mdls -name kMDItemContentType Tests/Fixtures/full-1.1.gpx` shows `com.topografix.gpx`
- [ ] `lsregister -dump | grep -A12 com.topografix.gpx` shows the GPX Preview import
- [ ] `qlmanage -p Tests/Fixtures/full-1.1.gpx` shows the track plot, not XML text
- [ ] `qlmanage -p Tests/Fixtures/malformed-unclosed.gpx` shows the error card with the file name and reason, not a crash or blank preview
- [ ] `qlmanage -t -s 512 -o /tmp/qlout Tests/Fixtures/full-1.1.gpx` writes a route thumbnail
- [ ] Finder: spacebar on a `.gpx` shows the preview; icon and column view show the route thumbnail
- [ ] System Settings → General → Login Items & Extensions → Quick Look lists both extensions, enabled
- [ ] First launch: Gatekeeper "Open Anyway" works as described in [README.md](README.md#gatekeeper-open-anyway)

`lsregister` lives at
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`.
