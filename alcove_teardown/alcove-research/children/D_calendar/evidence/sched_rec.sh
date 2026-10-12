#!/bin/bash
# usage: sched_rec.sh HH:MM:SS name seconds  -> waits until local time then records top 320 rows
target=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $1" +%s)
now=$(date +%s); [ $target -gt $now ] && sleep $((target-now))
echo "start $(date)" > ~/alcove-research/clips/$2.log
bash ~/alcove-research/rec_top.sh "$2" "$3" 320 >> ~/alcove-research/clips/$2.log 2>&1
echo "end $(date)" >> ~/alcove-research/clips/$2.log
