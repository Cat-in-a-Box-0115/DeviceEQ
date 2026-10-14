# Privacy

DeviceEQ captures audio for outputs whose EQ you enable using macOS Core Audio process taps. It processes buffers locally and does not save audio recordings, upload audio, use a microphone recording API, capture your screen, collect analytics or contact a network service during normal use. Disabled outputs do not start a processing route. macOS requires system-audio recording permission for enabled outputs.

Device names, persistent device identifiers, EQ settings and presets are saved locally in `~/Library/Application Support/DeviceEQ/profiles.json`. This retains existing profiles across updates. Backup/export writes only when you choose a destination. No accounts or credentials are required.

Diagnostics may contain device names/identifiers. Review and redact these before posting an issue; never include private audio or your full profile backup unless you intend to share it. Quit stops processing; uninstall retains profiles so you can restore them.
