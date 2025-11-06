#!/usr/bin/env bash
# Gatekeeper for VEI final deliveries (Option B hardened)
# Usage:
#   ./tools/verify_assets.sh assets_pub/*
#   ./tools/verify_assets.sh path/to/VEI_intro_main_10s_1080p_v1.mp4
set -euo pipefail

TARGET_LUFS="-14"     # streaming norm
TP_CEILING="-1.0"     # dBTP ceiling
DMIN=8                 # min duration (s)
DMAX=10                # max duration (s)

# Name schema: VEI_<asset>_<variant>_<dur>s_<res>_v<ver>.(mp4|mov)
VID_REGEX='^VEI_[A-Za-z0-9]+_[A-Za-z0-9]+_[0-9]+s_(1080p|2160p|9x16|1x1)_v[0-9]+\.(mp4|mov)$'

need() { command -v "$1" >/dev/null || { echo "Missing: $1" >&2; exit 2; }; }
need ffprobe
need ffmpeg

pass() { printf "\033[32mPASS\033[0m  %s\n" "$*"; }
warn() { printf "\033[33mWARN\033[0m  %s\n" "$*"; }
fail() { printf "\033[31mFAIL\033[0m  %s\n" "$*" >&2; }

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <file> [file ...]" >&2
  exit 2
fi

rc=0
shopt -s nullglob
for f in "$@"; do
  [ -f "$f" ] || { fail "No such file: $f"; rc=1; continue; }
  base="$(basename "$f")"

  # 1) Filename schema gate
  if [[ ! "$base" =~ $VID_REGEX ]]; then
    fail "Name schema → VEI_<asset>_<variant>_<dur>s_(1080p|2160p|9x16|1x1)_v#.(mp4|mov): $base"
    rc=1; continue
  fi

  # 2) Duration
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  dur=$(printf "%.2f" "$dur")
  awk "BEGIN{exit !($dur>=$DMIN && $dur<=$DMAX)}" || { fail "Duration ${DMIN}-${DMAX}s: $base ($dur s)"; rc=1; continue; }

  # 3) Video stream checks
  read -r vcodec w h fr prof < <(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,avg_frame_rate,profile \
    -of default=nk=1:nw=1 "$f")
  ext="${base##*.}"
  if [[ "$ext" == "mp4" && "$vcodec" != "h264" ]]; then fail "mp4 must be h264: $base ($vcodec)"; rc=1; continue; fi
  if [[ "$ext" == "mov" && "$vcodec" != "prores" ]]; then fail "mov must be prores: $base ($vcodec)"; rc=1; continue; fi
  if [[ "$fr" != "24000/1001" && "$fr" != "30000/1001" ]]; then fail "FPS must be 23.976 or 29.97: $base ($fr)"; rc=1; continue; fi

  # 4) Audio loudness (skip if no audio)
  if ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" >/dev/null 2>&1; then
    summary=$(ffmpeg -hide_banner -nostats -i "$f" -af loudnorm=I=$TARGET_LUFS:TP=$TP_CEILING:print_format=summary -f null - 2>&1 || true)
    I=$(awk -F': ' '/Input I:/{gsub(/ LUFS/,"",$2); print $2}' <<< "$summary")
    TP=$(awk -F': ' '/Input True Peak:/{gsub(/ dBTP/,"",$2); print $2}' <<< "$summary")
    # Allow ±1 LUFS window
    awk "BEGIN{exit !(($I <= ($TARGET_LUFS+1)) && ($I >= ($TARGET_LUFS-1)))}" || { fail "LUFS ~ $TARGET_LUFS: $base (I=$I)"; rc=1; continue; }
    awk "BEGIN{exit !($TP <= $TP_CEILING)}" || { fail "True-peak ≤ $TP_CEILING dBTP: $base (TP=$TP)"; rc=1; continue; }
  else
    warn "No audio stream: $base (skipping LUFS/TP)"
  fi

  pass "$base  ${w}x${h} @ ${fr}, ${dur}s"
done

exit $rc
