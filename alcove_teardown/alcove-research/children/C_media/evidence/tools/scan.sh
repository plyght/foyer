#!/bin/bash
# usage: scan.sh "label" "dx:dy,dx:dy,..."   -> performs one gesture over the compact notch, probes, moves away
cd ~/alcove
./tools/evt move 800 14 >/dev/null; sleep 0.4
echo "== $1  seq=$2"
./tools/evt swipeseq 800 14 "$2" 16 | tail -1
sleep 0.7; python3 probe.py
./tools/evt move 800 500 >/dev/null; sleep 1.2
