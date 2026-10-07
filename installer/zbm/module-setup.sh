#!/bin/bash
# dracut module "kaiseki-zbm": kaiseki's look for ZFSBootMenu. Adds two hooks to the image, nothing else.
check() { return 255; }                 # only when asked for (add_dracutmodules)
depends() { echo zfsbootmenu; }
install() {
    inst_simple "$moddir/10-kaiseki-console" /libexec/hooks/early-setup.d/10-kaiseki-console
    inst_simple "$moddir/10-kaiseki-unlock" /libexec/hooks/load-key.d/10-kaiseki-unlock
    chmod 755 "$initdir/libexec/hooks/early-setup.d/10-kaiseki-console" "$initdir/libexec/hooks/load-key.d/10-kaiseki-unlock"
    inst_multiple stty dd date cut
    # the wordmark as raw pixels, in two sizes, drawn onto the framebuffer (build-zbm.sh renders them)
    local f; for f in logo.bgra logo.dim logo-large.bgra logo-large.dim logo-small.bgra logo-small.dim; do inst_simple "$moddir/$f" "/usr/share/kaiseki/$f"; done
    # the two main screens in kaiseki's layout: functions that replace ZFSBootMenu's, sourced from its profile
    inst_simple "$moddir/kaiseki-ui.sh" /lib/kaiseki-ui.sh
    inst_simple "$moddir/kaiseki-chrome" /libexec/kaiseki-chrome; chmod 755 "$initdir/libexec/kaiseki-chrome"
    # (ZFSBootMenu refuses to start if sourcing its profile returns non-zero, so this line must always succeed)
    echo 'if [ -r /lib/kaiseki-ui.sh ] && [ "$(type -t draw_be)" = function ]; then source /lib/kaiseki-ui.sh; fi; true' >> "$initdir/etc/profile"
}
