#!/bin/bash
set -euo pipefail
DEST=${1:-/Applications/DeviceEQ.app}
if pgrep -x DeviceEQ >/dev/null; then
  echo 'Quit DeviceEQ first so its endpoints are removed and direct audio restored.' >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  mkdir -p "$HOME/.Trash"
  mv "$DEST" "$HOME/.Trash/DeviceEQ.$(date +%Y%m%d%H%M%S).app"
fi
echo 'App moved to Trash. No audio driver was installed.'
echo 'Your profiles remain in ~/Library/Application Support/DeviceEQ for reinstall or backup.'
echo 'System Settings > Privacy & Security > Screen & System Audio Recording manages the permission separately.'
