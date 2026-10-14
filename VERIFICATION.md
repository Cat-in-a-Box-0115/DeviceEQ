# Verification

## Automated checks

`./Tests/verify.sh` builds and runs independent rendered-sine DSP, response/headroom, bypass, limiter, invalid configuration, concurrent publication, stability and APO-parser checks; it also verifies the built bundle signature. Import fixtures are synthetic. These checks do not request permissions or emit sound.

## Local hardware evidence

Development testing on a MacBook Pro and AirPods Pro stereo at 48 kHz measured -12 dB and -18 dB changes to within 0.00001 dB of the intended gain; bypass measured approximately 0 dB. AirPods native volume readback followed 50% -> 25% -> 50%. No clipping or oversized blocks were reported in these bounded checks. A real Squiglink parametric export imported successfully through the file picker, including skipping its unused OFF/zero placeholder. The downloaded preset and personal device diagnostics are not distributed in this repository.

Saved AirPods EQ resumed after the HAL output disappeared/reappeared. Two enabled physical routes ran independently. Clean quit/relaunch with both profiles enabled passed after serializing HAL work off the UI thread. This is limited digital evidence, not analog/acoustic certification.

## Limitations and manual checks

Physical media keys, Bluetooth microphone/telephone mode, HDMI, multichannel audio, real sleep/wake, live rate changes, end-to-end latency and extended dropout/CPU measurements remain unqualified. Native physical volume control is preserved; fixed-volume hardware cannot gain hardware volume support from this design.

For an opt-in live physical-route test, quit all app copies first, grant permission yourself, and run the installed executable with `--verify-physical REPORT_PATH DEVICE_UID`. It emits quiet bounded test tones, temporarily changes output volume and restores it. Inspect and redact output/device identifiers before sharing. Do not run this mode during normal listening. Historical public-endpoint test modes remain internal helpers and do not represent the current UI's routing.

UI checks: edit gain and preset name; click a non-editable area and verify typing no longer enters the old field; click another field and verify it receives focus; press Escape to finish; Save/Undo should preserve the committed value. Confirm toolbar/Dock icon and menu-bar name, and on/off status for the current output.

## Version 0.3 UI checks

The installed application was tested with text-field clicks and keyboard input. Outside clicks committed a -3 dB gain edit, removed focus, and subsequent typing did not alter it. Profile-name input behaved the same; Escape also finished editing. Temporary settings were undone. A saved profile displayed its name and menu checkmark; changing preamp switched the header to Custom EQ · unsaved, and Undo restored its saved label. The toolbar displayed the new original flat response-curve icon. Dock icon loading explicitly uses the same bundled artwork; menu drawing shares the same geometry.

## Version 0.3.1 icon update

The installed bundle rebuilt and passed strict signature verification. Its editor displayed the new response-curve artwork. The shared curve renderer was inspected at active animation phases and at inactive (flat) state; a paired animated preview is provided outside the source archive. Menu animation uses 16 cached frames at 8 fps and reads the existing current-output EQ state; Reduce Motion selects a static active curve. Audio processing code was unchanged.

## Version 0.3.3 checks

Offline rendered DSP, stability, APO parser, isolated model regressions, and strict bundle signature checks passed. Model checks cover explicit enable clearing comparison, Undo/Redo preserving routing flags, rapid toggle intent, saved-profile identity, same-name replacement, persisted reload, and stalled-route state. The sidebar was visually checked with the new response-curve badge at the right of the device name and separate On/Paused/Off/Starting/Unavailable labels.

Initial installed-bundle digital physical-route checks on speakers and AirPods at 48 kHz passed: -12/-18 dB within 0.00001 dB; bypass within 0.00001 dB of unity. Output selection and original volume restored; AirPods volume changed from 37.5% to 25% and back. No clipping or oversized blocks were reported in these bounded checks.

A subsequent reconnect/startup test exposed a Core Audio stall in IOProc start/creation/teardown; a standalone speaker test also stalled afterward. Removed HAL reads from the device-list listener, added a 10-second startup state timeout and 5-second quit fallback. Recovery after restarting macOS audio, repeat reconnect, switching/bypass, and two-route relaunch still require live verification. Do not interpret the earlier digital passes as qualification of this stalled session or all reconnection cases. The installed UI subsequently displayed Unavailable after the startup timeout, and Command-Q successfully exited through the bounded shutdown fallback. Personal filters were preserved.

## Version 0.3.4 controls and resumed live checks

Removed both comparison controls and app/menu output-selection actions. Verified their absence in the installed UI. Existing paused-profile migration passed isolated model tests; bands and named presets are retained.

After a macOS restart, speakers started successfully and on/off transitions passed. Native System Settings output selection was tested between AirPods, speakers and the USB DAC. AirPods and speaker routes independently reported started=1, invalid=0 and advancing callbacks; the selected physical route followed macOS. The DAC stayed disabled/unprocessed. Quiet bounded 997 Hz tones were captured by each intended active route with no clipping or oversized blocks reported. Relaunch with AirPods and speakers enabled restored both routes, with DAC off.

eqMac had relaunched after the Mac restart and its virtual DAC was selected. Closed eqMac for the final DeviceEQ checks. One initial new-bundle startup exceeded the 10-second UI threshold and subsequently recovered automatically; later relaunch restored both routes promptly. These observations do not establish that all Core Audio stalls or Bluetooth reconnection cases are resolved.

Final version 0.3.4 installed-executable digital physical-route tests passed for speakers and AirPods: wet -12 dB, updated -18 dB and unity bypass each within 0.00001 dB; original native volume and default output restored. This bypass is an internal DSP verification mode, not a user comparison control.


## Version 0.3.5 UI and Settings

- Build, DSP/stability, APO parser, isolated model persistence/regression, and strict bundle signing checks passed.
- Native Settings opened with the toolbar gear and Command-comma. Launch-at-login registration toggled on successfully and was restored to off; a full logout/login cycle was not performed.
- Menu-bar visibility toggled off and back on. Closing the editor left the existing application process running; reopening the app restored the editor.
- Tested layout first in an isolated preview with 20 bands and no audio observation or personal profile access. Main editor is a constrained fixed container; EQ band scrolling changes only band position. Installed application screenshot confirmed complete header, graph, controls and footer.
- Initial unconstrained layout regressed and was rolled back before correction; final implementation uses an explicit detail viewport and the previous bounded band list.
- No DSP or routing changes in this version. AirPods disconnected during UI testing, so continuous live-audio playback while closed was not requalified.

TopNotch reference: REA static inspection of the installed version 1.3.2 identified LSUIElement and application-reopen/status-menu declarations. This is declaration evidence, not a runtime behavior claim; no code was copied. Evidence IDs: ev_8a5700edd90d08bcd48dd67fa3397264542fb369ff2d29c6ec9f594bd4b2b3f1 and ev_bd4d622d609a111058d2bb68e801d252a4ac1b63896c7372e6c85ed8582ea362.


## Version 0.3.6 layout polish

Build, DSP/stability, parser, model regression and strict signature checks passed. Isolated native preview with 20 test bands confirmed the device-name status badge and bottom-aligned actions/profile controls; no Last action box remains. Only the band list scrolls in the editor. Import/export/save failures retain visible feedback through a dismissible alert. Audio DSP and routing are unchanged.


## Version 0.3.7 flexible band list and profile chooser

Automated DSP/stability, parser, model regression and strict bundle checks passed. In the isolated native preview, the band list filled the remaining height at both normal and zoomed window sizes. The saved-profile popover opened above its bottom-row button; selecting Reference closed the popover and restored that test profile's preamp. All preview profiles were isolated from personal profiles and audio observation was disabled.


## Version 0.3.8 display performance and alignment

- DSP, 72,900 stability transitions, APO parser, isolated model and strict signing checks passed. No audio DSP or capture-path change.
- New display-cache regression tests compare every cached response point and effective preamp directly against DSP, and verify invalidation for EQ edits, preamp, rate and channel.
- 64-band benchmark on the development Mac: initial headroom/response calculation 58.08 ms; 100 cached reads 0.07 ms. This measures calculation cost, not scrolling frame rate.
- Native isolated preview checked alignment, scrolling to the final band, normal/zoomed layout, Routing & status, Settings, and manual preamp enabled/disabled when Auto headroom toggles. Preview profiles remain separate from personal data.
- Saved manual preamp is preserved; automatic headroom semantics are unchanged.

## Version 0.4.0 first-run guide and packaging

- Build, DSP/stability, parser, isolated model persistence and strict bundle checks passed. A fresh preference suite verifies guide dismissal persistence independently of device profiles.
- Installed native UI checked all four guide pages visually, Back/Next, Finish, Skip, Help replay and Settings replay. The guide fits its fixed sheet without text truncation. Navigation did not enable EQ or request audio permission. Relaunch did not show the dismissed guide again.
- Corrected editor-window identification to exclude the macOS Settings window. Settings retained the system window identifier, and its guide button raised the editor.
- Local source/app archives pass ZIP integrity checks and have SHA-256 checksums. Source packaging excludes .git, build, dist and local audio evidence.
- Audio processing is unchanged. Current hardware session had only built-in speakers connected; Bluetooth/DAC reconnect, active audio and scrolling FPS were not requalified in this release.
- The generated app archive is an ad-hoc signed local development build. No Developer ID signing, notarization, clean-Mac download or GitHub publication was performed.
- Extracted the versioned source ZIP into a clean temporary directory and built it independently; its complete automated test suite and signature checks passed.

## Version 0.4.1 profile management

- DSP/stability, parser, model and strict bundle checks passed. Added regressions for case/whitespace matching, delete/Undo/Redo/reload, preserved live EQ/routing, legacy duplicate-name cleanup, active identity, reserved suffixes, idempotence and unsaved import names.
- An isolated native preview verified deletion of an active saved entry without changing the current preamp, Undo restoration, Update profile for a case/space variation, and no extra saved entry after updating. Finder revealed the isolated profiles.json file.
- Installed chooser showed legacy duplicates under distinct names, with the current entry retaining its name/checkmark and delete controls present. A before/after integrity fingerprint confirmed existing EQ settings and all saved preset contents/identities were preserved, excluding names and inferred active identity.
- DSP and audio routing are unchanged; no live hardware audio qualification was repeated in this release.

## Version 0.4.2 editor tour and profile safeguards

- DSP/stability, parser, model and strict bundle checks passed. Added checks for unchanged-save detection, headroom edits/storage/loading and legacy ceiling flags ignored by the app's DSP configuration.
- Isolated native preview checked all seven section spotlights visually, Done, and the unchanged Update button. Updating/deleting showed named confirmation dialogs; Cancel preserved saved entries, confirmed Update disabled the button again, and Undo restored a confirmed deletion. Preview used disposable profiles without audio observation.
- Installed native UI checked first-run tour, Skip and Settings replay, concise accessibility help text, absence of Safety ceiling/Restore profiles, and Cat-in-a-Box credit in both Settings and the standard About panel.
- Presets now retain Auto headroom. Legacy presets without this field use the original default (on). No hard clipping is applied by the app, including when old JSON contains limiter=true. Filters, preamp and device routing continue to load normally.
- No live acoustic, Bluetooth reconnect or scrolling FPS qualification was repeated. Release packages remain local/ad-hoc signed until Developer ID signing and notarization.

## Version 0.4.3 UI polish

The full automated checks and strict bundle signature verification passed. A disposable audio-disabled preview verified all seven tour navigation steps, flat card/buttons, and the spotlight without the clipped blue outline. The five-band shortcut created zero-gain peak filters at 60, 250, 1,000, 4,000 and 12,000 Hz; Undo restored the previous profile. Normal and zoomed editor layouts retained the pinned actions/profile rows with the permanent import hint removed. Audio processing and routing code were unchanged.

## Version 0.4.4 appearance

Automated regressions and strict bundle signature checks passed. Installed Settings was checked with System, Light and Dark selections; the editor and Settings switched together. The Light choice was confirmed in persisted app preferences, then returned to System. Audio and route settings were not changed.

## Version 0.4.5 band selection

Build and strict bundle signature checks passed, as did DSP, stability, parser and model regressions during this change. An isolated audio-disabled preview verified the row selection button toggles its highlight and tooltip back off without changing filter values. Graph hit-testing now selects within 12 screen points of a band, with separate tap and drag gestures; drags require 3 points of movement. The pointer automation did not produce a reliable Canvas gesture result, so empty-graph taps and point dragging still require a manual native interaction check. Device changes and selected-band deletion clear the selection. Audio processing was unchanged.

## Version 0.4.6 graph styling

Build and strict signature verification passed. The installed light-mode editor was visually checked: the graph has no grey fill and uses a thin secondary-color rounded border; grid and curve remain visible. The border ignores pointer hits and the graph retains its rectangular gesture area. No audio or selection logic changed.

## Version 0.4.7 graph spacing

Build and strict signature checks passed. Installed light-mode graph visually checked without the outer container outline. Right margin increased to 24 points and bottom margin to 24 points, keeping the 20k label clear of the editor edge. Drawing, hit-testing and drag conversion use the same revised plot dimensions. Audio processing was unchanged.

## Version 0.4.8 editor cleanup

Build and strict bundle signature verification passed. The installed windowed editor was visually checked: the EQ badge is vertically centered beside the device name, the five-band shortcut is absent, Undo/Redo use arrow icons with accessible names and hover help, and Import/Export fit without truncated labels. The redundant per-device profile line is now hover help. DSP and saved-profile behavior were unchanged.
