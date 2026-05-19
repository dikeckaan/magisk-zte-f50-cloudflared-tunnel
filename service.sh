#!/system/bin/sh
# Cloudflare Tunnel service — late_start.

DATADIR=/data/cloudflared
TOKEN_FILE="$DATADIR/token"
LOG="$DATADIR/cloudflared.log"
BIN=/system/bin/cloudflared
METRICS_PORT=20241

mkdir -p "$DATADIR"

# bin-utils v1.3.0+ provides lib/common.sh (hard requirement).
. /data/adb/modules/bin-utils/lib/common.sh

# Wait up to 5 minutes for the user to drop the tunnel token into place.
wait_for_file "$TOKEN_FILE" 300 5 || {
    log_line "FATAL: no $TOKEN_FILE after 5 min"
    exit 1
}

# Wait for network (max ~1 min, check every 2s).
i=0
while ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; do
    i=$((i+1))
    [ $i -ge 30 ] && break
    sleep 2
done

# Pick the best health-check probe. The original used `nc -w 2 ... PORT`
# but `nc` isn't on stock Android and isn't in bin-utils — every probe
# failed silently and unhealthy daemons were never killed. We try in order:
#   1. bash's /dev/tcp (always available via bin-utils' bash)
#   2. nc (if it ever shows up)
#   3. /proc/net/tcp grep for LISTEN state on the metrics port
PORT_HEX=$(printf '%04X' "$METRICS_PORT")
HEALTH_BASH=$(find_bash 2>/dev/null)
health_ok() {
    if [ -n "$HEALTH_BASH" ]; then
        "$HEALTH_BASH" -c "exec 3<>/dev/tcp/127.0.0.1/$METRICS_PORT" 2>/dev/null
        return $?
    fi
    if command -v nc >/dev/null 2>&1; then
        echo "" | nc -w 2 127.0.0.1 "$METRICS_PORT" >/dev/null 2>&1
        return $?
    fi
    grep -qE ":${PORT_HEX} 00000000:0000 0A " /proc/net/tcp 2>/dev/null
}

# Supervisor loop with health monitoring.
(
    while true; do
        log_rotate 5242880   # 5 MB

        TOKEN=$(cat "$TOKEN_FILE")
        log_line "starting cloudflared"
        "$BIN" tunnel --no-autoupdate --retries 3 --grace-period 30s \
                      run --token "$TOKEN" >> "$LOG" 2>&1 &
        CF_PID=$!

        # Give cloudflared time to start and register connections.
        sleep 20

        fail_count=0
        while kill -0 "$CF_PID" 2>/dev/null; do
            sleep 15
            if health_ok; then
                fail_count=0
            else
                fail_count=$((fail_count + 1))
                log_line "health check failed ($fail_count/4)"
                if [ $fail_count -ge 4 ]; then
                    log_line "unhealthy for 60s, killing cloudflared (pid $CF_PID)"
                    kill "$CF_PID" 2>/dev/null
                    sleep 3
                    kill -9 "$CF_PID" 2>/dev/null
                    break
                fi
            fi
        done

        wait "$CF_PID" 2>/dev/null
        log_line "cloudflared exited, restarting in 5s"
        sleep 5
    done
) &
