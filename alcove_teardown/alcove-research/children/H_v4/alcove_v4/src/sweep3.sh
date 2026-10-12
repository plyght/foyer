#!/bin/bash
# B3: (a) reset threshold: up 30, reverse down R, up 30 again (from calendar-visible). (b) slow 160px gestures (40 steps x 40ms) for in-gesture fire point + animation timing.
cd ~/alcove_v4; tag=$1; csv=csv/${tag}.csv
echo "idx,wall,phase,dir,dist,rep,reverseAt,swipe_t0,swipe_dir,swipe_dist,swipe_rev,steps,intervalMs,thirdLeg" > $csv
pkill -x ffmpeg; sleep 1
nohup ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -c:v libx264 -preset ultrafast -crf 18 clips/${tag}.mp4 > /tmp/ff_${tag}.log 2>&1 &
sleep 3; ./src/mv 800 400; sleep 0.5
i=0
g() { # phase dir dist rep reverseAt steps interval third
  i=$((i+1)); out=$(./src/swipe 800 10 $2 $3 $6 $7 $5 $8); echo "$i,$(date +%T.%N),$1,$2,$3,$4,$5,$out" >> $csv; sleep 2.2; ./src/mv 800 400; sleep 0.5; }
for R in 0 5 10 15 20 25 30 40 50; do for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g test_reset up $R $rep 30 12 8 30; done; done
# control: up 30 alone, and up 60 alone
for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g ctrl_up30 up 30 $rep 0 12 8 0; done
for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g slow_up up 160 $rep 0 40 40 0; done
for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g prep_up up 100 $rep 0 12 8 0; g slow_down down 160 $rep 0 40 40 0; done
for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g slow_left left 160 $rep 0 40 40 0; done
for rep in 1 2 3; do g restore down 120 $rep 0 12 8 0; g slow_right right 160 $rep 0 40 40 0; done
sleep 2; pkill -INT -x ffmpeg; echo "done $(date +%T.%N)" >> $csv
