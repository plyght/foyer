#!/bin/bash
# B4: expanded-state sweep. Open expanded by clicking the notch, swipe over the expanded panel at (800,60).
cd ~/alcove_v4; tag=$1; csv=csv/${tag}.csv
echo "idx,wall,phase,dir,dist,rep,reverseAt,swipe_t0,swipe_dir,swipe_dist,swipe_rev,steps,intervalMs,thirdLeg" > $csv
pkill -x ffmpeg; sleep 1
nohup ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -c:v libx264 -preset ultrafast -crf 18 clips/${tag}.mp4 > /tmp/ff_${tag}.log 2>&1 &
sleep 3; ./src/mv 800 400; sleep 0.5
i=0
for dir in up down left right; do for dist in $(seq 20 10 160); do for rep in 1 2; do
  i=$((i+1)); ./src/mv 800 10 click; sleep 1.3
  out=$(./src/swipe 800 60 $dir $dist 12 8 0 0); echo "$i,$(date +%T.%N),expanded,$dir,$dist,$rep,0,$out" >> $csv
  sleep 2.0; ./src/mv 800 400; sleep 1.2
done; done; done
sleep 2; pkill -INT -x ffmpeg; echo "done $(date +%T.%N)" >> $csv
