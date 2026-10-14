# DeviceEQ usage guide

## Using the editor

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

## Processing status

The response-curve badge sits to the right of each device name. **On** means its EQ route is running; **Off**, **Starting**, **Unavailable** and **Disconnected** describe the other states. The menu-bar animation follows the current macOS output, not merely the device selected in the editor.

Legacy comparison pauses are cleared automatically when profiles load. Undo/Redo changes saved EQ edits without restoring old enable/bypass settings. Saving an existing profile name updates that profile rather than adding another duplicate.

## Managing saved profiles

Each row in Choose profile has a delete button. Deletion asks for confirmation, then removes the saved entry while leaving current EQ and routing unchanged; Undo restores it. Names are unique per output, ignoring case and surrounding spaces. Saving an existing name shows **Update profile**, disabled when nothing changed. Updating asks for confirmation before replacing the entry. Profiles also retain Auto headroom. Older duplicates are kept under unique names such as `Reference (2)`; the active entry keeps its name. Older stored profiles follow the same naming rules.

**Show in Finder** reveals `profiles.json` in the local DeviceEQ folder. Copy that file to keep a backup of all device profiles. The file contains device identifiers, so review it before sharing.
