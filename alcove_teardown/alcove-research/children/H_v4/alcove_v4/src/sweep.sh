#!/bin/bash
# usage: sweep.sh <tag> <compact|expanded> <dir...>   (sweep 20-160 px step 5, 3 repeats)
cd ~/alcove_v4
tag=$1; state=$2; shift 2
csv=csv/${tag}.csv
echo "idx,wall,state,dir,dist,rep,reverseAt,swipe_t0,swipe_dir,swipe_dist,swipe_rev,steps,intervalMs" > $csv
pkill -x ffmpeg; sleep 1
nohup ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -c:v libx264 -preset ultrafast -crf 18 clips/${tag}.mp4 > /tmp/ff_${tag}.log 2>&1 &
sleep 3
./src/mv 1590 1190; echo "marker,$(date +%T.%N),$state,,,,,,,,,," >> $csv; sleep 1.0
./src/mv 800 400; sleep 0.5
i=0
for dir in "$@"; do for dist in $(seq 20 5 160); do for rep in 1 2 3; do
  i=$((i+1))
  if [ "$state" = expanded ]; then ./src/mv 800 10 click; sleep 1.2; fi
  out=$(./src/swipe 800 10 $dir $dist)
  echo "$i,$(date +%T.%N),$state,$dir,$dist,$rep,0,$out" >> $csv
  sleep 2.0
  ./src/mv 800 400; sleep 0.4
done; done; done
sleep 2; pkill -INT -x ffmpeg; echo "done $(date +%T.%N)" >> $csv
