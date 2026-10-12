#!/bin/bash
# Runs Foyer's demo walkthrough on a macOS CI runner and collects screenshots,
# a screen recording, crops, a GIF and logs into $OUT.
set -uo pipefail

APP="${1:?path to Foyer.app}"
OUT="${2:-capture}"
DEMO_DIR="$(mktemp -d)/demo"
BIN="$APP/Contents/MacOS/Foyer"
mkdir -p "$OUT/screens" "$OUT/crops" "$DEMO_DIR"

log() { echo "[capture] $*"; }

# Screen geometry (points) for crops around the notch.
read -r SW SH <<<"$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame; f.size.width+" "+f.size.height' 2>/dev/null || echo "1920 1080")"
SCALE="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.mainScreen.backingScaleFactor' 2>/dev/null || echo 1)"
log "screen ${SW}x${SH} @${SCALE}x"

crop() { # crop the 624x320 notch panel region, scaled to pixels
  local src="$1" dst="$2"
  local w h x
  w=$(python3 -c "print(int(624*$SCALE))"); h=$(python3 -c "print(int(320*$SCALE))")
  x=$(python3 -c "print(int(($SW*$SCALE - 624*$SCALE)/2))")
  ffmpeg -loglevel error -y -i "$src" -vf "crop=$w:$h:$x:0,scale=iw*2:ih*2:flags=neighbor" "$dst" || true
}

# Settings for a deterministic run on a notchless virtual display.
defaults write app.foyer.Foyer isFirstLaunch -bool false
defaults write app.foyer.Foyer forceSimulatedNotch -bool true
defaults write app.foyer.Foyer automaticallyCheckForUpdates -bool false
defaults write app.foyer.Foyer idleActivity -string calendar

# A test tone so the real Now Playing path (QuickTime → MediaRemote) has media.
TONE="$OUT/tone.m4a"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=120" \
  -metadata title="Foyer Test Tone — A Long Title That Should Scroll In The Marquee" \
  -metadata artist="Foyer CI" -metadata album="Capture" -c:a aac "$TONE" || true

# Screen recording of the whole run.
ffmpeg -loglevel error -f avfoundation -capture_cursor 1 -framerate 30 -i "Capture screen 0:none" \
  -t 240 -pix_fmt yuv420p "$OUT/run.mp4" </dev/null &
REC=$!
sleep 2

log "launching demo"
"$BIN" -FoyerDemo YES -FoyerDemoDir "$DEMO_DIR" >"$OUT/app-stdout.log" 2>&1 &
APP_PID=$!

sleep 3
open -a "QuickTime Player" "$TONE" || true
osascript -e 'tell application "QuickTime Player" to play document 1' >/dev/null 2>&1 || \
  { sleep 3; osascript -e 'tell application "QuickTime Player" to play document 1' >/dev/null 2>&1 || true; }

# Screenshot every marker as it appears.
SEEN=""
for _ in $(seq 1 900); do
  for marker in "$DEMO_DIR"/*.ready; do
    [ -e "$marker" ] || continue
    name="$(basename "$marker" .ready)"
    case " $SEEN " in *" $name "*) continue ;; esac
    SEEN="$SEEN $name"
    screencapture -x "$OUT/screens/$name.png"
    crop "$OUT/screens/$name.png" "$OUT/crops/$name.png"
    echo "$name: $(cat "$marker")" >>"$OUT/steps.txt"
    log "captured $name"
  done
  [ -e "$DEMO_DIR/done" ] && break
  kill -0 "$APP_PID" 2>/dev/null || { log "app exited early"; break; }
  sleep 0.2
done

sleep 2
kill "$APP_PID" 2>/dev/null || true
osascript -e 'tell application "QuickTime Player" to quit saving no' >/dev/null 2>&1 || true
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

# Onboarding: a fresh first launch.
log "capturing onboarding"
defaults write app.foyer.Foyer isFirstLaunch -bool true
"$BIN" >>"$OUT/app-stdout.log" 2>&1 &
ONB=$!
sleep 6
screencapture -x "$OUT/screens/onboarding.png"
kill "$ONB" 2>/dev/null || true

# Derived media: a notch-region clip and GIF.
if [ -s "$OUT/run.mp4" ]; then
  W=$(python3 -c "print(int(624*$SCALE))"); H=$(python3 -c "print(int(320*$SCALE))")
  X=$(python3 -c "print(int(($SW*$SCALE - 624*$SCALE)/2))")
  ffmpeg -loglevel error -y -i "$OUT/run.mp4" -vf "crop=$W:$H:$X:0" -pix_fmt yuv420p "$OUT/notch.mp4" || true
  ffmpeg -loglevel error -y -i "$OUT/notch.mp4" -vf "fps=15,scale=624:-1:flags=lanczos" "$OUT/notch.gif" || true
fi

# Logs and crash reports.
log show --last 10m --style compact --predicate 'process == "Foyer" OR process == "FoyerHelper"' >"$OUT/unified.log" 2>/dev/null || true
mkdir -p "$OUT/crashes"
cp ~/Library/Logs/DiagnosticReports/Foyer* "$OUT/crashes/" 2>/dev/null || true

# Summary for the Actions run page.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Foyer UI capture"
    echo
    echo "Steps captured: $(ls "$OUT/crops" 2>/dev/null | wc -l | tr -d ' ')"
    echo
    echo '```'
    cat "$OUT/steps.txt" 2>/dev/null
    echo '```'
    [ -n "$(ls "$OUT/crashes" 2>/dev/null)" ] && echo "**Crash reports found** — see the artifact."
  } >>"$GITHUB_STEP_SUMMARY"
fi
log "done"
