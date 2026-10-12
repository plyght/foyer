#!/bin/bash
# usage: rec.sh name seconds  -> ~/alcove/clips/name.mp4 (60fps, full screen 1600x1200)
cd ~/alcove/clips
echo "rec-start $(python3 -c 'import time;print(f"{time.time():.3f}")')"
ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -t "$2" -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p "$(basename "$1").mp4"
ffprobe -v error -select_streams v -show_entries stream=width,height,r_frame_rate,nb_frames -of csv=p=0 "$(basename "$1").mp4"
