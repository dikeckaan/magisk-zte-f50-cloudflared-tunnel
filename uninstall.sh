#!/system/bin/sh

# Stop supervisor + cloudflared (match by full path to avoid colliding with other tools)
pkill -f /system/bin/cloudflared 2>/dev/null
pkill -f "service.sh" 2>/dev/null
killall cloudflared 2>/dev/null

# Keep /data/cloudflared (token + logs) for reinstall.
# Manual cleanup: rm -rf /data/cloudflared
