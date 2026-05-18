#!/system/bin/sh
# Cloudflare Tunnel service - runs after boot in late_start service mode

DATADIR=/data/cloudflared
TOKEN_FILE="$DATADIR/token"
LOGFILE="$DATADIR/cloudflared.log"
LOG_MAX_BYTES=5242880   # 5 MB
BIN=/system/bin/cloudflared
METRICS_PORT=20241

mkdir -p "$DATADIR"

# Wait for token file (set by user post-install)
i=0
while [ ! -s "$TOKEN_FILE" ]; do
  i=$((i+1))
  [ $i -ge 60 ] && exit 1
  sleep 5
done

# Wait for network (max ~1 min, check every 2s)
i=0
while ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; do
  i=$((i+1))
  [ $i -ge 30 ] && break
  sleep 2
done

# Supervisor loop with health monitoring
(
  while true; do
    # Rotate log if too big
    if [ -f "$LOGFILE" ]; then
      size=$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
      if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        mv "$LOGFILE" "$LOGFILE.1"
      fi
    fi

    TOKEN=$(cat "$TOKEN_FILE")
    echo "[$(date)] starting cloudflared" >> "$LOGFILE"

    "$BIN" tunnel --no-autoupdate --retries 3 --grace-period 30s run --token "$TOKEN" >> "$LOGFILE" 2>&1 &
    CF_PID=$!

    # Give cloudflared time to start and register connections
    sleep 20

    # Health check: verify metrics port is responding
    fail_count=0
    while kill -0 "$CF_PID" 2>/dev/null; do
      sleep 15
      if echo "" | nc -w 2 127.0.0.1 "$METRICS_PORT" >/dev/null 2>&1; then
        fail_count=0
      else
        fail_count=$((fail_count + 1))
        echo "[$(date)] health check failed ($fail_count/4)" >> "$LOGFILE"
        if [ $fail_count -ge 4 ]; then
          echo "[$(date)] unhealthy for 60s, killing cloudflared (pid $CF_PID)" >> "$LOGFILE"
          kill "$CF_PID" 2>/dev/null
          sleep 3
          kill -9 "$CF_PID" 2>/dev/null
          break
        fi
      fi
    done

    wait "$CF_PID" 2>/dev/null
    echo "[$(date)] cloudflared exited, restarting in 5s" >> "$LOGFILE"
    sleep 5
  done
) &
