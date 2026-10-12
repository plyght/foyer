#!/bin/bash
# Alcove hardware performance capture for a real notched Mac.
# Run from fish with:  bash ~/Downloads/alcove_hw_perf.sh
# Needs sudo once (powermetrics). Takes about 5 minutes. Writes ~/alcove_hw_perf.tgz
set -u
OUT=~/alcove_hw_perf; rm -rf "$OUT"; mkdir -p "$OUT"; cd "$OUT"
PID=$(pgrep -x Alcove) || { echo "Start Alcove first"; exit 1; }
sudo -v || exit 1
{ sw_vers; sysctl -n machdep.cpu.brand_string hw.model; pmset -g batt; system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Refresh|Chipset"; defaults read /Applications/Alcove.app/Contents/Info CFBundleShortVersionString; } > system.txt 2>&1
phase() { # name seconds prompt
  echo; echo ">>> PHASE $1 ($2 s): $3"; read -r -p "Press Enter when ready..." _
  date -u +%FT%TZ > "$1.start"
  sudo powermetrics -i 1000 -n "$2" --samplers tasks,gpu_power,cpu_power --show-process-energy --show-process-gpu > "$1.powermetrics.txt" 2>&1 &
  PM=$!
  top -l "$2" -s 1 -pid "$PID" -stats pid,cpu,mem,idlew,power > "$1.top.txt" 2>&1
  wait $PM; footprint "$PID" > "$1.footprint.txt" 2>&1
  echo "done $1"
}
phase idle 60 "Leave the Mac alone, notch closed, nothing playing."
phase openclose 60 "Hover/click the notch open and closed repeatedly for the whole minute."
phase nowplaying 60 "Play a song in Music or Spotify (Live waveform on if you use it); keep the notch closed."
phase nowplaying_open 30 "Keep music playing and keep the notch expanded."
phase volume 30 "Tap volume up/down (and brightness keys) continuously."
phase battery 60 "Optional: unplug the charger now (skip by pressing Enter and leaving it plugged)."
vmmap --summary "$PID" > vmmap.txt 2>&1
cd ~ && tar czf alcove_hw_perf.tgz alcove_hw_perf && echo "Send me ~/alcove_hw_perf.tgz"
