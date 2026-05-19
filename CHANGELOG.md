# Changelog

## v1.2.2 — 2026-05-19
- **Service migration to `bin-utils/lib/common.sh`** (now a hard dep,
  v1.3.0+ required). `service.sh` uses `wait_for_file` for the token
  wait, `find_bash` for the /dev/tcp health probe, `log_line` and
  `log_rotate` from the shared library. Net: 97 → 85 lines.
- **NEW `customize.sh`** to enforce the bin-utils dependency at install
  time (no customize.sh existed before — it was a pure file-overlay
  module). Aborts cleanly if `lib/common.sh` is missing.
- Behaviour unchanged: same supervisor with 4-fail health threshold,
  same fallback chain in `health_ok()` (bash /dev/tcp → nc → /proc/net/tcp).

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
