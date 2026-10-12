#!/bin/bash
# usage: clip.sh name secs 'shell commands...'   (commands run ~1.0s after ffmpeg starts; log timestamps go to clips/name.actions)
name=$1; secs=$2; shift 2
cd ~/alcove
( ./rec.sh "$name" "$secs" > clips/$name.log 2>&1 & )
sleep 1.0
python3 -c "import time;print(f'{time.time():.3f} actions-begin')" > clips/$name.actions
( eval "$@" ) >> clips/$name.actions 2>&1
sleep $(( secs + 1 ))
grep -E "rec-start|^1600" clips/$name.log; cat clips/$name.actions
