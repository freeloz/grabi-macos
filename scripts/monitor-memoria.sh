#!/bin/zsh
# Prueba de resistencia (FASE D2): monitorea la memoria de Grabi mientras
# grabas 30-60 min. La memoria NO debe crecer de forma sostenida (el motor
# escribe en streaming a disco, nunca acumula en RAM).
#
# Uso: ./scripts/monitor-memoria.sh [salida.csv]   (Ctrl+C para terminar)
OUT=${1:-grabi-memoria.csv}
echo "tiempo,rss_mb" > "$OUT"
echo "Monitoreando Grabi cada 10 s → $OUT (Ctrl+C para parar)"
while true; do
  PID=$(pgrep -x Grabi | head -1)
  if [[ -n "$PID" ]]; then
    RSS=$(ps -o rss= -p "$PID" | awk '{printf "%.1f", $1/1024}')
    LINE="$(date +%H:%M:%S),$RSS"
    echo "$LINE" | tee -a "$OUT"
  else
    echo "$(date +%H:%M:%S),app no corriendo"
  fi
  sleep 10
done
