#!/bin/bash
# poll Alcove sockets every 0.5s and log new (host:port,state) tuples with timestamps
seen=""
while true; do
  for l in $(lsof -nP -i -a -p "$(pgrep -x Alcove | head -1)" 2>/dev/null | awk 'NR>1{print $9"|"$10}'); do
    if [[ "$seen" != *"$l"* ]]; then echo "$(date +%T.%N) $l"; seen="$seen $l"; fi
  done
  sleep 0.5
done
