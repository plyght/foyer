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

# Screen geometry: measure a real screenshot (pixels) and the logical width.
screencapture -x "$OUT/screens/00-probe.png"
SW_PX=$(sips -g pixelWidth "$OUT/screens/00-probe.png" | awk '/pixelWidth/{print $2}')
SH_PX=$(sips -g pixelHeight "$OUT/screens/00-probe.png" | awk '/pixelHeight/{print $2}')
SW_PT=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 'UI Looks like' | grep -oE '[0-9]+ x [0-9]+' | awk '{print $1}')
[ -n "$SW_PT" ] || SW_PT=$SW_PX
SCALE=$(python3 -c "print(round($SW_PX/$SW_PT))")
log "screen ${SW_PX}x${SH_PX}px, ${SW_PT}pt wide, @${SCALE}x"

crop() { # crop the 624x320 notch panel region, scaled to pixels
  local src="$1" dst="$2"
  local w h x
  w=$(python3 -c "print(int(624*$SCALE))"); h=$(python3 -c "print(int(320*$SCALE))")
  x=$(python3 -c "print(int(($SW_PX - 624*$SCALE)/2))")
  ffmpeg -loglevel error -y -i "$src" -vf "crop=$w:$h:$x:0,scale=iw*2:ih*2:flags=neighbor" "$dst" || true
}

# Settings for a deterministic run on a notchless virtual display.
defaults write app.foyer.Foyer isFirstLaunch -bool false
defaults write app.foyer.Foyer forceSimulatedNotch -bool true
defaults write app.foyer.Foyer automaticallyCheckForUpdates -bool false
defaults write app.foyer.Foyer idleActivity -string calendar
# Pretend permissions were already asked so system prompts don't cover the screen.
for k in Accessibility Audio Bluetooth Calendar Location; do
  defaults write app.foyer.Foyer "hasPrompted${k}Permission" -bool true
done

# Screen recording of the whole run.
ffmpeg -loglevel error -f avfoundation -capture_cursor 1 -framerate 30 -i "Capture screen 0:none" \
  -t 240 -pix_fmt yuv420p "$OUT/run.mp4" </dev/null &
REC=$!
sleep 2

log "launching demo"
open -n "$APP" --stdout "$OUT/app-stdout.log" --stderr "$OUT/app-stderr.log" \
  --args -FoyerDemo YES -FoyerDemoDir "$DEMO_DIR"
sleep 1
APP_PID=$(pgrep -n -x Foyer || echo 0)
log "Foyer pid $APP_PID"

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
pkill -x Foyer 2>/dev/null || true
cp "$DEMO_DIR"/windows*.txt "$OUT/" 2>/dev/null || true
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

# Onboarding: a fresh first launch.
log "capturing onboarding"
defaults write app.foyer.Foyer isFirstLaunch -bool true
open -n "$APP" --stdout "$OUT/onboarding-stdout.log" --stderr "$OUT/onboarding-stderr.log"
sleep 6
screencapture -x "$OUT/screens/onboarding.png"
pkill -x Foyer 2>/dev/null || true

# Derived media: a notch-region clip and GIF.
if [ -s "$OUT/run.mp4" ]; then
  W=$(python3 -c "print(int(624*$SCALE))"); H=$(python3 -c "print(int(320*$SCALE))")
  X=$(python3 -c "print(int(($SW_PX - 624*$SCALE)/2))")
  ffmpeg -loglevel error -y -i "$OUT/run.mp4" -vf "crop=$W:$H:$X:0" -pix_fmt yuv420p "$OUT/notch.mp4" || true
  ffmpeg -loglevel error -y -i "$OUT/notch.mp4" -vf "fps=15,scale=624:-1:flags=lanczos" "$OUT/notch.gif" || true
fi

# Logs and crash reports.
sudo log show --last 10m --style compact --predicate 'process == "Foyer" OR process == "FoyerHelper"' >"$OUT/unified.log" 2>/dev/null || true
mkdir -p "$OUT/crashes"
cp ~/Library/Logs/DiagnosticReports/Foyer* "$OUT/crashes/" 2>/dev/null || true
sudo cp /Library/Logs/DiagnosticReports/Foyer* "$OUT/crashes/" 2>/dev/null || true

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
