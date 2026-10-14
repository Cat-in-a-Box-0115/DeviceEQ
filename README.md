# DeviceEQ

<p align="center"><img src="Assets/DeviceEQ-icon.png" alt="DeviceEQ icon" width="128"></p>

<p align="center"><strong>A lightweight, free, open source parametric EQ for macOS. No audio driver required.</strong></p>

DeviceEQ is a native macOS parametric equalizer with independent settings for each output device. Enable EQ for headphones, speakers or AirPods; their normal sound output and native volume controls remain available. Outputs with EQ off play normally. Processing uses Apple's Core Audio process taps, so there is no virtual audio device or kernel/HAL driver to install.

**Requirements:** Apple Silicon Mac, macOS 14.2 or later. This is an early development release; see [verification](VERIFICATION.md) for tested behavior and limitations.

## Highlights

- Per-device EQ profiles that follow each output (speakers, AirPods, USB DACs) and survive disconnects
- Up to 64 parametric bands: peak, low/high shelf, high/low pass and notch, per channel or stereo
- Import Squiglink, AutoEq and Equalizer APO parametric presets; export back to APO text
- Auto headroom, undo/redo, named presets, live response graph
- Keeps macOS output selection and native volume keys working
- About 2 MB, no telemetry, no account, no network access

## Screenshots

_Screenshots coming soon._

<!-- Add images under docs/screenshots/ and reference them here, e.g.
![Editor](docs/screenshots/editor.png) -->

## Install

Prebuilt app ZIPs are attached to [Releases](../../releases). They are ad-hoc signed and not notarized, so on first launch right-click DeviceEQ.app and choose **Open**, then grant system-audio permission when asked. To build it yourself instead, follow the steps below.

## Build and install

Install Apple's Command Line Tools (`xcode-select --install`), then run from this repository:

```sh
./build.sh
./Tests/verify.sh
./install.sh
```

The build is self-contained: Swift, C++ and Apple's frameworks, with no package downloads or Python dependency. The app is built at `build.noindex/DeviceEQ.app`. Installation preserves an existing DeviceEQ app as a verified timestamped ZIP backup. For an existing DeviceEQ installation, quit it first; DeviceEQ reads the same saved profiles. Keep only one running copy.

The default build is locally ad-hoc signed. It is not notarized. macOS may request system-audio permission again when a locally rebuilt executable changes. Official distributable releases require the maintainer's Developer ID certificate and notarization; see [release instructions](RELEASING.md).

## Getting started

A skippable editor tour highlights the device list, EQ switch, graph, headroom, bands, actions and saved profiles in place. Navigation never changes EQ or switches output. Reopen it from **Help → Setup guide…**, Settings or the menu bar.

## Use

1. Select a device in the sidebar.
2. Add bands, or choose **Import**. For Squiglink use **Export Parametric EQ**, then import the `.txt` file. AutoEq / Equalizer APO parametric presets also work. Graphic EQ / Wavelet exports are not supported.
3. Enable **EQ for this device**. Select its normal output in macOS’s sound menu. The saved EQ applies when that output is available, including AirPods stereo reconnects.
4. Turn **EQ for this device** off to return to normal playback.
5. Save named presets for multiple analog headphones on one DAC; macOS cannot identify which analog headphone is attached.

Click outside a text field, press Return, or press Escape to finish editing. The menu bar uses the same response-curve mark as the app icon: a gently moving curve means EQ is active on the current output, and a still flat line means EQ is off or unavailable. The app icon also appears in the editor toolbar and Dock.

## Settings and background operation

Open **DeviceEQ → Settings…**, press **⌘,**, or use the gear in the editor. Options include System/Light/Dark appearance, launch at login, menu-bar visibility, keeping EQ running after closing the editor, and showing the Dock icon in the background. Closing the editor keeps processing running by default; **Quit DeviceEQ** stops it. When the menu-bar icon is hidden, the Dock remains available so you can reopen the app. Login registration uses Apple’s ServiceManagement framework and displays any required macOS approval.

The editor itself stays fixed; the EQ band list scrolls. EQ status appears beside the device name, and band actions and profile controls stay at the bottom. The band list fills the space above them as you resize the window. Choose profile opens upward, with scrolling for longer profile lists. At narrower window sizes controls wrap and the graph becomes shorter to keep the controls reachable.

The manual preamp field is disabled while Auto headroom is on. Its saved value is retained and still acts as an upper bound for automatic attenuation; turning Auto headroom off makes it editable again.

## Features and audio quality

- Up to 64 parametric bands; peak, shelves, high/low pass and notch; stereo or independent channels.
- Dense frequency graph, editable preamp, optional auto headroom, presets, undo/redo, APO export and profile storage/recovery.
- Float32 PCM I/O with double-precision filter coefficients/state, no added codec conversion, DSP resampling, spatialization or normalization.
- EQ changes both amplitude and phase. Use adequate headroom to prevent clipping. Auto headroom includes 0.1 dB safety attenuation, so a flat enabled profile is not bit-perfect.
- No hard clipping/ceiling is added. Legacy Safety ceiling flags are ignored. Auto headroom reduces clipping risk; downstream outputs can still clip if you boost without enough headroom.
- Bluetooth telephone/microphone modes, HDMI and multichannel outputs are not qualified. Stereo physical outputs at a supported matching format are required. Fixed-volume hardware remains fixed-volume.

## Privacy and removal

Audio is processed locally, with no telemetry or account. [Privacy details](PRIVACY.md). System-audio permission is required only for processing enabled devices.

Quit, then run `./uninstall.sh` to move the app to Trash. Profiles remain in `~/Library/Application Support/DeviceEQ` for recovery. No custom audio driver is installed.

## Release packages

After building and testing, run `./Scripts/package-release.sh`. It writes versioned source/app ZIPs and SHA-256 checksums under `dist/`. The default app ZIP is a local development build, not notarized. See [release instructions](RELEASING.md) and the [release checklist](RELEASE_CHECKLIST.md) for official distribution.

## Contributing and license

[MIT license](LICENSE). Vibe coded by Cat-in-a-Box. [Attribution](THIRD_PARTY_NOTICES.md). [Contribution guide](CONTRIBUTING.md). Source includes deterministic DSP/parser tests; live audio checks are opt-in and require reviewing the instructions. Do not publish personal device diagnostics or headphone measurement data without permission.

The product name remains DeviceEQ while a future name is considered.

The header shows the active saved profile, or **Custom EQ · unsaved** after settings change. **Choose profile** marks the active profile; when none have been saved, the menu says **No saved profiles**.

Regenerate original icon assets with `./Scripts/generate-icon.sh`.

The menu-bar motion indicates processing status, not a live audio measurement. With macOS Reduce Motion enabled, active EQ shows a still curved line. Icon frames are cached, and the inactive image is not redrawn continuously.

Build outputs live in `build.noindex/` so macOS launchers do not discover extra app copies. ZIP backups remain recoverable without adding launcher icons.

## Processing status

The response-curve badge sits to the right of each device name. **On** means its EQ route is running; **Off**, **Starting**, **Unavailable** and **Disconnected** describe the other states. The menu-bar animation follows the current macOS output, not merely the device selected in the editor.

Legacy comparison pauses are cleared automatically when profiles load. Undo/Redo changes saved EQ edits without restoring old enable/bypass settings. Saving an existing profile name updates that profile rather than adding another duplicate.

## Managing saved profiles

Each row in Choose profile has a delete button. Deletion asks for confirmation, then removes the saved entry while leaving current EQ and routing unchanged; Undo restores it. Names are unique per output, ignoring case and surrounding spaces. Saving an existing name shows **Update profile**, disabled when nothing changed. Updating asks for confirmation before replacing the entry. Profiles also retain Auto headroom. Older duplicates are kept under unique names such as `Reference (2)`; the active entry keeps its name. Older stored profiles follow the same naming rules.

**Show in Finder** reveals `profiles.json` in the local DeviceEQ folder. Copy that file to keep a backup of all device profiles. The file contains device identifiers, so review it before sharing.

Vibe coded by **Cat-in-a-Box**. Credit is also shown in Settings and About DeviceEQ.
