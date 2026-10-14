# Roadmap

DeviceEQ stays a **lightweight, audio-only parametric EQ**. Per-app mixing, volume boost, spatial effects and networking are deliberately out of scope.

## Next
- Notarization is deferred: releases stay free, ad-hoc signed downloads (the README explains the one-time Open Anyway step). The release script is ready if that changes.
- Screenshots and a short demo GIF in the README
- Universal (Intel + Apple Silicon) builds: `ARCHS="arm64 x86_64" ./build.sh` works and the DSP/model tests pass under Rosetta; needs testing on a real Intel Mac before release

## Qualification (needs real hardware)
- Manual checks of graph dragging and band deselection
- Idle/active CPU and memory with realistic band counts
- Sleep/wake, sample-rate changes, Bluetooth reconnects, USB DACs

## Good first issues
See the issues labelled `good first issue`, and [docs/QA.md](docs/QA.md) for hands-on test steps.
