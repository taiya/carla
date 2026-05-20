#!/usr/bin/env bash
# comparison_video.sh — assemble a 2×2 comparison video from captured frame sets.
#
# Layout:
#   ┌──────────────────┬──────────────────┐
#   │  default         │  no_postprocess  │
#   ├──────────────────┼──────────────────┤
#   │  no_vignette     │  diff (no_vig    │
#   │                  │  vs default, ×10)│
#   └──────────────────┴──────────────────┘
#
# Usage:
#   OUTPUT_DIR=/workspace/output/carla VIDEO_FPS=20 ./comparison_video.sh
#   or via Makefile: make video.comparison

set -euo pipefail

OUTDIR="${OUTPUT_DIR:-/workspace/output/carla}"
FPS="${VIDEO_FPS:-20}"
FONT_SIZE=36

TL="$OUTDIR/default/frames/%06d.png"
TR="$OUTDIR/no_postprocess/frames/%06d.png"
BL="$OUTDIR/no_vignette/frames/%06d.png"
OUT="$OUTDIR/comparison.mp4"

echo "==> Building comparison video: $OUT"

ffmpeg -y \
  -framerate "$FPS" -i "$TL" \
  -framerate "$FPS" -i "$TR" \
  -framerate "$FPS" -i "$BL" \
  -framerate "$FPS" -i "$TL" \
  -framerate "$FPS" -i "$BL" \
  -filter_complex "
    [0:v]drawtext=text='default':fontsize=${FONT_SIZE}:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.6:boxborderw=4[tl];
    [1:v]drawtext=text='no postprocess':fontsize=${FONT_SIZE}:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.6:boxborderw=4[tr];
    [2:v]drawtext=text='no vignette':fontsize=${FONT_SIZE}:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.6:boxborderw=4[bl];
    [3:v][4:v]blend=all_mode=difference,
      eq=contrast=10:saturation=0,
      drawtext=text='diff (no_vignette - default\, x10)':fontsize=${FONT_SIZE}:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.6:boxborderw=4[br];
    [tl][tr][bl][br]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[out]
  " \
  -map "[out]" \
  -c:v libx264 -pix_fmt yuv420p \
  "$OUT"

echo "==> Done: $OUT"
