#!/bin/zsh
# Endurance test (PHASE D2): monitors Grabi's memory while you record for
# 30-60 min. Memory must NOT grow steadily (the engine streams to disk,
# it never accumulates in RAM).
#
# Usage: ./scripts/monitor-memory.sh [output.csv]   (Ctrl+C to finish)
OUT=${1:-grabi-memory.csv}
echo "time,rss_mb" > "$OUT"
echo "Monitoring Grabi every 10 s → $OUT (Ctrl+C to stop)"
while true; do
  PID=$(pgrep -x Grabi | head -1)
  if [[ -n "$PID" ]]; then
    RSS=$(ps -o rss= -p "$PID" | awk '{printf "%.1f", $1/1024}')
    LINE="$(date +%H:%M:%S),$RSS"
    echo "$LINE" | tee -a "$OUT"
  else
    echo "$(date +%H:%M:%S),app not running"
  fi
  sleep 10
done
