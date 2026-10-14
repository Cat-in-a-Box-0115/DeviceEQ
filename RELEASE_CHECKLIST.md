# Release checklist

- [ ] Build and run `./Tests/verify.sh` on Apple Silicon with supported macOS.
- [ ] Open the editor tour on a fresh preference domain; check every spotlight at normal/zoomed sizes, Skip/Done, dismissal persistence and Help/Settings replay.
- [ ] Check device selection, empty/disconnected outputs, EQ import/export, malformed import feedback, save/load, unchanged Update disabled, update/delete confirmation and cancellation, Undo recovery and Show in Finder.
- [ ] Resize the editor; only bands scroll, actions stay reachable, profile chooser stays above its button.
- [ ] Check keyboard editing, outside-click dismissal, Auto headroom, undo/redo, and light/dark appearance.
- [ ] Qualify supported hardware: permission, EQ on/off, native volume, switching, reconnect, quit/relaunch, background and login behavior.
- [ ] Review `VERIFICATION.md`; report remaining unqualified hardware/behavior in release notes.
- [ ] Review license/attribution, privacy, source archive and version numbers; exclude private profiles and diagnostics.
- [ ] Package with `./Scripts/package-release.sh --local`. (Optional, paid membership only: notarize with `./Scripts/notarize-release.sh` instead.)
- [ ] Verify published checksums and test the downloaded artifact on a clean Mac before calling it ready for general use.

Releases are currently not notarized; the README explains the one-time Open Anyway step for users. This checklist records work to perform; unchecked items are not claims of validation.
