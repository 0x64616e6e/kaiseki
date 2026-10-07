#!/bin/bash
# dracut module "kaiseki-zbm": kaiseki's look for ZFSBootMenu. Adds two hooks to the image, nothing else.
check() { return 255; }                 # only when asked for (add_dracutmodules)
depends() { echo zfsbootmenu; }
install() {
    inst_simple "$moddir/10-kaiseki-console" /libexec/hooks/early-setup.d/10-kaiseki-console
    inst_simple "$moddir/10-kaiseki-unlock" /libexec/hooks/load-key.d/10-kaiseki-unlock
    chmod 755 "$initdir/libexec/hooks/early-setup.d/10-kaiseki-console" "$initdir/libexec/hooks/load-key.d/10-kaiseki-unlock"
    inst_multiple stty
}
