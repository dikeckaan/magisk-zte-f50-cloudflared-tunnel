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

    # Health check helper. The original used `nc -w 2 ... PORT` but `nc`
    # isn't shipped on stock Android and isn't in bin-utils, so the check
    # always failed silently and unhealthy daemons were never killed.
    # We pick the best available probe, in order:
    #   1. bash's /dev/tcp (if bash is installed via bin-utils)
    #   2. nc (if it ever shows up)
    #   3. /proc/net/tcp (always present; checks LISTEN state)
    PORT_HEX=$(printf '%04X' "$METRICS_PORT")
    HEALTH_BASH=
    for p in /system/bin/bash /data/adb/modules/bin-utils/system/bin/bash; do
      [ -x "$p" ] && HEALTH_BASH="$p" && break
    done
    health_ok() {
      if [ -n "$HEALTH_BASH" ]; then
        "$HEALTH_BASH" -c "exec 3<>/dev/tcp/127.0.0.1/$METRICS_PORT" 2>/dev/null
        return $?
      fi
      if command -v nc >/dev/null 2>&1; then
        echo "" | nc -w 2 127.0.0.1 "$METRICS_PORT" >/dev/null 2>&1
        return $?
      fi
      # Last-resort: kernel says port is LISTEN (0x0A). Doesn't verify
      # the daemon answers, but if cloudflared crashed the socket is gone.
      grep -qE ":${PORT_HEX} 00000000:0000 0A " /proc/net/tcp 2>/dev/null
    }

    fail_count=0
    while kill -0 "$CF_PID" 2>/dev/null; do
      sleep 15
      if health_ok; then
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
