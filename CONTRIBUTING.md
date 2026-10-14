# Contributing

Use Apple Silicon/macOS 14.2+ and Apple's Command Line Tools. Build with `./build.sh`, then run `./Tests/verify.sh`. Keep real-time audio callbacks free of allocation, blocking, filesystem access and UI work. Validate preset changes before committing them and preserve per-device isolation.

Include the macOS version, app version, expected/actual behavior and reproduction steps in an issue. Redact device identifiers and personal profile names. Never attach audio recordings, credentials, full backups or third-party measurement datasets by default.

Changes to routing require explicit opt-in live hardware testing; offline tests alone do not establish output isolation, volume behavior or latency. Contributions use the project's MIT license. Do not copy proprietary app code or assets.
