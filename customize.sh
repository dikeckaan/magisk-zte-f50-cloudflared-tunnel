#!/system/bin/sh
ui_print " "
ui_print "  Cloudflare Tunnel v1.2.1+"
ui_print "  =========================="
ui_print " "
ui_print "  Outbound tunnel daemon with supervisor + health check."
ui_print "  Token: drop your tunnel token at /data/cloudflared/token"
ui_print "         then reboot (or invoke service.sh manually)."
ui_print " "

# Hard dependency: bin-utils v1.3.0+ for lib/common.sh (find_bash, log_line,
# log_rotate, wait_for_file). The service.sh sources it directly; we abort
# at install time rather than letting the supervisor fail at boot.
if [ ! -r /data/adb/modules/bin-utils/lib/common.sh ] \
   && [ ! -r /data/adb/modules_update/bin-utils/lib/common.sh ]; then
    ui_print " "
    ui_print "  ❌ bin-utils v1.3.0+ is required (lib/common.sh missing)."
    ui_print "     Install it first: /install_module bin-utils"
    ui_print " "
    abort "  Missing dependency: bin-utils v1.3.0+"
fi

set_perm "$MODPATH/system/bin/cloudflared" 0 0 0755
set_perm "$MODPATH/service.sh"             0 0 0755

ui_print "  [OK] Installed. Reboot to start the tunnel."
ui_print " "
