#!/bin/bash
# usage: rec_top.sh name seconds [height]  -> records only top H rows of the display at 60fps
cd ~/alcove-research/clips
H=${3:-300}
ffmpeg -y -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -t "$2" -vf "crop=1600:$H:0:0" -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p "$(basename "$1").mp4"
ffprobe -v error -select_streams v -show_entries stream=width,height,r_frame_rate,nb_frames -of csv=p=0 "$(basename "$1").mp4"
