#!/bin/bash
set -e

PATCH_SRC="/home/sysop/host_shared/docker_overrides/shakemap_patches"
PY_SITE="/usr/local/lib/python3.9/site-packages"

echo "=== Applying ShakeMap patches as root ==="

if [ -d "$PATCH_SRC" ]; then
    cp -f "$PATCH_SRC"/utils/amps.py "$PY_SITE/shakemap_modules/utils/amps.py"
    cp -f "$PATCH_SRC"/coremods/assemble.py "$PY_SITE/shakemap_modules/coremods/assemble.py"
    mkdir -p /home/sysop/.strec
    cp -f "$PATCH_SRC"/config.ini /home/sysop/.strec/config.ini
  
    # Copy the moment tensor database
    cp -f "/usr/local/lib/python3.9/site-packages/strec/data/moment_tensors.db" "/home/sysop/.strec/moment_tensors.db"

    # # SeisComp related patches: ShakeMap trigger python script
    # mkdir -p /home/sysop/.seiscomp/scripts/run_events
    # cp -f "$PATCH_SRC"/seiscomp_shakemap/*.py "/home/sysop/.seiscomp/scripts/run_events/"
    # chown -R sysop:sysop /home/sysop/.seiscomp/scripts/run_events
    # chmod +x /home/sysop/.seiscomp/scripts/run_events/*.py

    # # Trigger scripts for ShakeMap from scalert. Goes to /opt/seiscomp/etc
    # cp -f "$PATCH_SRC"/seiscomp_shakemap/pyshakemap.py "/opt/seiscomp/etc/"
    # chmod +x "/opt/seiscomp/etc/pyshakemap.py"
    # chown sysop:sysop "/opt/seiscomp/etc/pyshakemap.py"

    # cp -f "$PATCH_SRC"/seiscomp_shakemap/runshakemap.sh "/opt/seiscomp/etc/"
    # chmod +x "/opt/seiscomp/etc/runshakemap.sh"
    # chown sysop:sysop "/opt/seiscomp/etc/runshakemap.sh"

    echo "Patches applied."
else
    echo "WARNING: Patch source folder not found: $PATCH_SRC"
fi