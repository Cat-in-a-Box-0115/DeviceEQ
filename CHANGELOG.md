# Changelog

## 0.4.8

- Remove the five-band shortcut and simplify the editor action row.
- Use accessible Undo/Redo icons, followed by Reset, and plain Import/Export labels.
- Center the status badge beside the device name and move the repeated per-device profile explanation to hover help.

## 0.4.7

- Remove the graph container outline and give endpoint labels more breathing room.
- Keep graph hit-testing and drag coordinates aligned with the revised plot margins.

## 0.4.6

- Replace the EQ graph’s grey fill with a subtle theme-aware outline.

## 0.4.5

- Deselect bands by clicking empty graph space or toggling their selection button.
- Start graph edits only near a band point; selection clicks no longer alter EQ.
- Clear selection when switching devices or deleting the selected band.

## 0.4.4

- Add persisted System, Light and Dark appearance options in Settings, applied across app windows.

## 0.4.3

- Remove the permanent import-format hint from the editor.
- Flatten tour cards/buttons and retain the spotlight without an edge outline.
- Replace the 20-band shortcut with five flat, editable parametric bands.

## 0.4.2

- Replace the setup sheet with a section-highlighted editor tour.
- Confirm saved-profile updates/deletions; disable Update when unchanged.
- Save Auto headroom with profiles and remove Restore profiles.
- Remove Safety ceiling from the app and ignore its legacy flags in playback.
- Add concise hover descriptions and Cat-in-a-Box credit in Settings/About.

## 0.4.1

- Delete saved profiles from the chooser, with Undo/Redo and unchanged current EQ.
- Treat case and surrounding spaces as the same profile name; show Update profile for an existing name.
- Preserve legacy duplicate profiles under unique names, keeping the active profile identity.
- Replace Back up profiles with Show in Finder to reveal the local profile file.

## 0.4.0

- Add a skippable first-run setup guide with live device selection and processing status.
- Reopen the guide from Help, Settings or the menu bar; navigating never changes EQ or requests audio permission.
- Add versioned local/release packaging and SHA-256 checksums, with clean source archives.
- Add public bug-report and release-testing templates.

## 0.3.8

- Cache headroom and frequency-response display calculations by EQ, rate and channel.
- Create the bounded set of band controls before scrolling; avoid lazy row creation and repeated unchanged device publications.
- Center mixed-height controls and align numeric columns with their headings.
- Disable the saved manual preamp field while Auto headroom is on.

## 0.3.7

- Expand the scrollable EQ band list into the available space above the bottom controls.
- Open the saved-profile chooser in an upward popover with a bounded scrollable list.

## 0.3.6

- Place live EQ status beside the device name.
- Anchor band actions and profile controls at the bottom of the editor.
- Remove the Last action box; file-operation failures use a dismissible error alert.

## 0.3.5

- Add Settings for launch at login, menu-bar visibility, Dock visibility, and continuing EQ after closing the editor.
- Keep the main editor fixed while preserving EQ band scrolling.
- Wrap controls at narrower widths; constrain content to the window and shorten the graph when needed.
- Add balanced spacing around the existing toolbar badge.
- Keep a Dock access path when the menu-bar icon is hidden.

## 0.3.4

- Remove original-sound comparison and saved-profile graph comparison.
- Remove app and menu-bar output-selection actions; use the native macOS sound menu.
- Clear legacy comparison pauses while preserving EQ bands and presets.

## 0.3.3

- Move the matching response-curve status badge to the right of the device name.
- Show actual processing state independently from the last action message.
- Explicit enable resumes EQ after comparison; rapid off/on preserves final intent.
- Undo/Redo no longer restores stale routing/bypass flags.
- Re-saving a profile name updates its existing entry; track the selected saved profile.
- Keep HAL calls out of device-list listeners; poll connection/format on the control queue.
- Report stalled startup as unavailable after 10 seconds; allow quit after a 5-second teardown timeout.
- Add isolated model regression tests without audio capture or personal profile access.

## 0.3.2

- Keep build bundles in a non-indexed staging directory to prevent duplicate launcher entries.
- Archive previous installed apps as verified ZIP backups.

## 0.3.1

- Flat frequency-response app icon and matching menu-bar shape.
- Active EQ gently animates; inactive/bypassed EQ shows a still flat line.
- Respect macOS Reduce Motion and cache menu animation frames.

## 0.3.0

- Keep DeviceEQ identity and existing profiles.
- Clicking outside text inputs or pressing Escape ends editing.
- Flat monochrome Dock icon and matching menu-bar mark; visible editor branding.
- Explicit unsaved profile state and checkmarked saved profile selection.
- Remove obsolete correction search/fitting code and bundled Python runtime.
- Add source license, privacy/attribution docs, reproducible build, CI and release guide.
