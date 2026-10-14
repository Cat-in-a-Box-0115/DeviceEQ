# Hands-on QA checklist

These checks need a person at a real Mac with real outputs. Each takes a few minutes. Record results in the linked issue (macOS version, Mac model, output device, pass/fail, anything odd). Keep the volume low before enabling EQ.

## Graph selection and dragging (issue #2), about 3 minutes
1. Pick an output with at least 3 bands.
2. Click a band's point on the graph: its row highlights. Click empty graph space: selection clears and **no values change**.
3. Drag a point sideways and up/down: frequency and gain follow smoothly; Undo restores the previous values.
4. A tiny click without moving (under 3 pt) must not change the band.

## CPU and memory (issue #3), about 5 minutes
Run `./Scripts/measure-usage.sh 60` once for each scenario, with music playing for the active ones:
- EQ off on all outputs (idle)
- 10 bands on one output
- 64 bands on one output (Import a 64-band file or add bands)
- EQ on two outputs at once, if you have two connected
Paste each result into issue #3.

## Sleep, sample rate and Bluetooth (issue #4), about 10 minutes
With EQ on and music playing:
1. Sleep the Mac for a minute, wake it: EQ resumes without re-enabling, the badge returns to **On**.
2. In Audio MIDI Setup, change the output's sample rate (e.g. 48 kHz to 44.1 kHz): playback continues and the EQ still applies.
3. AirPods: put them in the case for 10 seconds, take them out: they reconnect with their EQ.
4. USB DAC: unplug and replug: same.
5. Quit and relaunch DeviceEQ: each output's EQ state is restored.

## Before each public release
Follow [RELEASE_CHECKLIST.md](../RELEASE_CHECKLIST.md), then `./Scripts/notarize-release.sh` (see [RELEASING.md](../RELEASING.md)).
