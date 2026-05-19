# Changelog

## v1.2.1 — 2026-05-19
- **Fixed**: Health check used `echo "" | nc -w 2 127.0.0.1 20241` to
  probe cloudflared's metrics port, but `nc` (netcat) is NOT shipped on
  stock Android and isn't in `bin-utils`. Every check failed silently,
  so the failure counter never incremented and unhealthy daemons were
  never killed.
- New `health_ok()` helper tries probes in order: bash's `/dev/tcp` (if
  bash is installed via `bin-utils`), then `nc` (if it ever appears),
  then `/proc/net/tcp` parsing for the LISTEN state on the metrics
  port. Always-available fallback means health checks now actually
  work on stock toybox-only devices.
- No changes to the cloudflared binary or supervisor loop structure.

## v1.2.0
- Initial public release
