# cloudflared-tunnel

Cloudflare Tunnel daemon (`cloudflared`) wrapped as a Magisk module for
rooted Android (ZTE F50 / Unisoc UMS9620). Lets you reach the device's
SSH and ADB ports from anywhere via Cloudflare Zero Trust, without
opening any inbound port on the carrier-grade NAT'd cellular link.

## Why

The ZTE F50 sits behind operator CGNAT — there's no usable inbound port.
Tailscale works but routes via the relay if peer-to-peer fails. A
Cloudflare named tunnel runs as an *outbound* WebSocket connection from
the device to Cloudflare's edge, so anything you expose (TCP, HTTP,
SSH, ADB) becomes reachable through your `*.cloudflareaccess.com`
hostnames, gated by your Zero Trust policy. Lower latency than relayed
Tailscale, no firewall holes needed.

## Install

```sh
# From statusbot in Telegram (recommended):
/install_module cloudflared-tunnel

# From any other shell:
adb push cloudflared-tunnel-vX.Y.Z.zip /sdcard/
adb shell su -c "magisk --install-module /sdcard/cloudflared-tunnel-vX.Y.Z.zip"
reboot
```

## Requires

- Magisk **26.0+**
- Android **arm64**
- **bin-utils v1.3.0+** — provides `lib/common.sh` (`log_line`,
  `log_rotate`, `wait_for_file`, `find_bash` used in `service.sh`)
- A Cloudflare account with a Zero Trust tunnel created
  (https://one.dash.cloudflare.com → Networks → Tunnels)

## Configuration

The module won't start the daemon until the tunnel token is in place:

```sh
# Drop your tunnel token (the long base64 string from `cloudflared tunnel token <name>`)
echo "<token>" > /data/cloudflared/token
chmod 600 /data/cloudflared/token

# Reboot or run service.sh manually
reboot
```

`service.sh` waits up to 5 minutes for the token to appear; if it
doesn't, the module logs a fatal line and exits cleanly (no daemon
restart loop chewing CPU).

## How it stays healthy

`service.sh` runs cloudflared under a supervisor loop that probes the
metrics port (default `127.0.0.1:20241`) every 15 seconds via:

1. bash's `/dev/tcp` pseudo-device (always works via bin-utils' static bash)
2. `nc` (rarely present on Android, kept as a fallback)
3. `/proc/net/tcp` grep for the `LISTEN` state on the metrics port (toybox-friendly last resort)

After 4 consecutive failures (~60 s) the daemon is killed and respawned.
The log at `/data/cloudflared/cloudflared.log` rotates at 5 MB.

## Bot integration

Statusbot's `/tunnel` (or `/cf`) command reports whether the daemon is
up, how long the tunnel has been running, and a snippet from the log.
There's no `/tunnel on|off` toggle — the module is meant to stay up; if
you want it off, uninstall.

## Files

| Path | Purpose |
|---|---|
| `/data/cloudflared/token`         | Your tunnel token (chmod 600). Required to start. |
| `/data/cloudflared/cloudflared.log` | Supervisor + daemon log, rotates at 5 MB |
| `/data/adb/modules/cloudflared-tunnel/service.sh` | Supervisor entry point |
| `/data/adb/modules/cloudflared-tunnel/system/bin/cloudflared` | Static arm64 binary, mounted as `/system/bin/cloudflared` |

## Uninstall

Magisk Manager → Modules → Remove. `uninstall.sh` stops the daemon and
its supervisor; it does NOT remove `/data/cloudflared/token` (so a
reinstall doesn't lose your tunnel binding). Delete manually with
`rm -rf /data/cloudflared` if you want a clean slate.

## License

GPL-3.0 (see [LICENSE](LICENSE)).
