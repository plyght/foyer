#!/bin/bash
# cycle-threshold sweep with state restore. usage: sweep2.sh <tag>
cd ~/alcove_v4; tag=$1; csv=csv/${tag}.csv
echo "idx,wall,phase,dir,dist,rep,reverseAt,swipe_t0,swipe_dir,swipe_dist,swipe_rev,steps,intervalMs" > $csv
pkill -x ffmpeg; sleep 1
nohup ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -c:v libx264 -preset ultrafast -crf 18 clips/${tag}.mp4 > /tmp/ff_${tag}.log 2>&1 &
sleep 3; ./src/mv 800 400; sleep 0.5
i=0
g() { # phase dir dist rep reverseAt
  i=$((i+1)); out=$(./src/swipe 800 10 $2 $3 12 8 $5); echo "$i,$(date +%T.%N),$1,$2,$3,$4,$5,$out" >> $csv; sleep 2.0; ./src/mv 800 400; sleep 0.5; }
DISTS="20 25 30 35 40 45 50 55 60 65 70 80 100 120 160"
# A) UP test from calendar-visible: restore(down120) then test up N
for dist in $DISTS; do for rep in 1 2 3; do g restore down 120 $rep 0; g test_up up $dist $rep 0; done; done
# B) DOWN test from np-visible with calendar dismissed: restore(down120), up100 (dismiss cal), test down N
for dist in $DISTS; do for rep in 1 2 3; do g restore down 120 $rep 0; g prep_up up 100 $rep 0; g test_down down $dist $rep 0; done; done
# C) reversal: from calendar-visible, move up 60 then reverse down R px (does dismiss still fire?)
for rev in 0 5 10 15 20 25 30 40 60; do for rep in 1 2 3; do g restore down 120 $rep 0; g test_rev up $rev $rep 60; done; done
sleep 2; pkill -INT -x ffmpeg; echo "done $(date +%T.%N)" >> $csv
