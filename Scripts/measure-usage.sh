#!/bin/bash
# Sample a running DeviceEQ's CPU and memory. Read-only: it does not change EQ, routing or volume.
# Usage: ./Scripts/measure-usage.sh [seconds]   (default 60). Set up the scenario first, e.g. EQ off,
# or 10/64 bands enabled on one or two outputs with music playing, then run this.
set -euo pipefail
SECONDS_TO_SAMPLE=${1:-60}
PID=$(pgrep -x DeviceEQ | head -1) || { echo 'DeviceEQ is not running.' >&2; exit 1; }
echo "Sampling DeviceEQ (pid $PID) for $SECONDS_TO_SAMPLE s..."
for _ in $(seq "$SECONDS_TO_SAMPLE"); do ps -o %cpu=,rss= -p "$PID"; sleep 1; done | awk '
  { cpu+=$1; if($1>maxc) maxc=$1; mem+=$2; if($2>maxm) maxm=$2; n++ }
  END { if(!n) exit 1; printf "CPU %%: avg %.1f, max %.1f\nMemory: avg %.1f MB, max %.1f MB (%d samples)\n", cpu/n, maxc, mem/n/1024, maxm/1024, n }'
sw_vers -productVersion | sed 's/^/macOS /'; sysctl -n machdep.cpu.brand_string
