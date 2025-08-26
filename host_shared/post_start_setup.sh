#!/usr/bin/env bash
set -euo pipefail

SYSOP_USER="${SYSOP_USER:-sysop}"
USER_HOME="/home/${SYSOP_USER}"
HOST_SHARED="${HOST_SHARED:-${USER_HOME}/host_shared}"
SEISCOMP_ROOT="${SEISCOMP_ROOT:-/opt/seiscomp}"


echo "=== Post-start setup (SeisComP + configs) ==="

# ---- Validate SeisComP root ----
if [ ! -d "$SEISCOMP_ROOT" ]; then
  echo "ERROR: SEISCOMP_ROOT directory $SEISCOMP_ROOT does not exist." >&2
  exit 1
fi

# ---- SeisComP configs (system + user) ----
SYS_SRC="$HOST_SHARED/docker_overrides/seiscomp_configs/system_seiscomp"
USER_SRC="$HOST_SHARED/docker_overrides/seiscomp_configs/user_home_seiscomp"
SYS_DEST="$SEISCOMP_ROOT/etc"
USER_DEST="$USER_HOME/.seiscomp"
# Fallback: if system_seiscomp does not exist, try legacy/typo folder name
if [ ! -d "$SYS_SRC" ] && [ -d "$HOST_SHARED/docker_overrides/seiscomp_configs/system_seiscom" ]; then
  SYS_SRC="$HOST_SHARED/docker_overrides/seiscomp_configs/system_seiscom"
fi
# Set flag to disable mbtiles plugin if requested
DISABLE_MBTILES="${DISABLE_MBTILES:-true}"

 [ -d "$SYS_SRC" ]  && cp -a "$SYS_SRC/."  "$SYS_DEST/"
 [ -d "$USER_SRC" ] && cp -a "$USER_SRC/." "$USER_DEST/"

# Copy FinDer configuration folder for user (if present)
if [ -d "$USER_SRC/FinDer-config" ]; then
  echo "Copying FinDer configuration for user..."
  mkdir -p "$USER_DEST/FinDer-config"
  cp -a "$USER_SRC/FinDer-config/." "$USER_DEST/FinDer-config/"
fi

# Copy the files under opt_seiscomp_etc to /opt/seiscomp/etc
cp -a "$HOST_SHARED/opt_seiscomp_etc/." "$SYS_DEST/"

# normalize connection.server to localhost (avoid host.docker.internal)
if [ -f "$USER_DEST/global.cfg" ]; then
  if grep -q "^connection\\.server" "$USER_DEST/global.cfg"; then
    sed -i 's|^connection\\.server.*|connection.server = localhost|' "$USER_DEST/global.cfg"
  else
    echo "connection.server = localhost" >> "$USER_DEST/global.cfg"
  fi
fi

# ---- Remove mbtiles plugin references (avoid plugin load failures) ----
if [ "$DISABLE_MBTILES" = "true" ]; then  
    for CFG in "$SYS_DEST/global.cfg" "$USER_DEST/global.cfg"; do
    if [ -f "$CFG" ]; then
        sed -i '/mbtiles/d' "$CFG" || true
    fi
    done
fi

# ---- SeisComP DB: point to mounted SQLite ----
DB_PATH="$HOST_SHARED/seiscomp_db/db.sqlite"
DB_URI="sqlite3://${HOST_SHARED}/seiscomp_db/db.sqlite"  # yields sqlite3:///absolute/path
mkdir -p "$(dirname "$DB_PATH")"
chown -R "${SYSOP_USER}:${SYSOP_USER}" "$(dirname "$DB_PATH")" || true
### Uncomment these if SeisComp was configured for sqlite3
# if [ -f "$USER_DEST/global.cfg" ]; then
#   if grep -q "dbPlugin" "$USER_DEST/global.cfg"; then
#     sed -i 's|^\s*dbPlugin\s*=.*|dbPlugin = dbsqlite3|' "$USER_DEST/global.cfg"
#   else
#     echo "dbPlugin = dbsqlite3" >> "$USER_DEST/global.cfg"
#   fi
#   if grep -q "^\s*database\s*=" "$USER_DEST/global.cfg"; then
#     sed -i "s|^\s*database\s*=.*|database = ${DB_URI}|" "$USER_DEST/global.cfg"
#   else
#     echo "database = ${DB_URI}" >> "$USER_DEST/global.cfg"
#   fi

#   # Ensure core.plugins includes dbsqlite3 (required by some versions)
#   if grep -q "^\s*core\.plugins" "$USER_DEST/global.cfg"; then
#     if ! grep -q "core\.plugins.*dbsqlite3" "$USER_DEST/global.cfg"; then
#       sed -i 's|^\s*core\.plugins\s*=.*|core.plugins = dbsqlite3|' "$USER_DEST/global.cfg"
#     fi
#   else
#     echo "core.plugins = dbsqlite3" >> "$USER_DEST/global.cfg"
#   fi
# fi

# ---- Initialize SQLite schema if DB is missing or empty ----
SCHEMA_FILE="$SEISCOMP_ROOT/share/db/sqlite3.sql"
if [ ! -f "$DB_PATH" ] || [ -z "$(sqlite3 "$DB_PATH" '.tables' 2>/dev/null)" ]; then
  echo "Initializing SQLite schema at $DB_PATH"
  mkdir -p "$(dirname "$DB_PATH")"
  : > "$DB_PATH"
  chown "${SYSOP_USER}:${SYSOP_USER}" "$DB_PATH" || true
  if [ -f "$SCHEMA_FILE" ]; then
    sqlite3 "$DB_PATH" < "$SCHEMA_FILE" || { echo "ERROR: Failed to load SQLite schema"; exit 1; }
    chown "${SYSOP_USER}:${SYSOP_USER}" "$DB_PATH" || true
  else
    echo "WARNING: Schema file not found at $SCHEMA_FILE"
  fi

  (sqlite3 -batch -init $SEISCOMP_ROOT/share/db/vs/sqlite3.sql $DB_PATH .exit && \
   sqlite3 -batch -init $SEISCOMP_ROOT/share/db/wfparam/sqlite3.sql $DB_PATH .exit)

fi

sed -i 's|^#\?recordstream *=.*|recordstream = slink://localhost:18000|' ~/.seiscomp/global.cfg

# ---- Seedlink FIFO binding profile: create proper bindings + assign to all stations ----
# Copy seedlink.cfg etc
cp "$HOST_SHARED/seedlink.cfg" "$USER_DEST/"

# Create the seedlink bindings directory and the 'fifo' profile with its sources file
BIND_DIR="$SEISCOMP_ROOT/etc/bindings/seedlink/"
mkdir -p "$BIND_DIR"

# List the available source-group(s). Must be just names, not "sources = ..."
printf "%s\n" "mseedfifo" > "$BIND_DIR/sources"

# Define the mseedfifo source-group so the renderer can produce a plugin block
cat > "$BIND_DIR/mseedfifo" <<'EOF'
plugins = mseedfifo

[mseedfifo]
fifo = /opt/seiscomp/var/run/seedlink/mseedfifo
EOF

# Ensure the seedlink key directory exists and set the default profile mapping
mkdir -p "$SEISCOMP_ROOT/etc/key/seedlink/"
printf "* fifo\n" > "$SEISCOMP_ROOT/etc/key/seedlink/profile"
printf "sources = mseedfifo\n" > "$SEISCOMP_ROOT/etc/key/seedlink/profile_fifo"

# Assign the 'fifo' profile to all NET.STA via the SeisComP shell (idempotent)
printf "set profile seedlink fifo *.*\nexit\n" | seiscomp shell || true

# Ensure the FIFO path exists and is writable
mkdir -p /opt/seiscomp/var/run/seedlink/
mkfifo /opt/seiscomp/var/run/seedlink/mseedfifo || true
chmod 666 /opt/seiscomp/var/run/seedlink/mseedfifo

# Build SeedLink config now that bindings exist (render seedlink.ini in one pass)
seiscomp update-config seedlink || true
# sanity: ensure the ini was created; if not, try once more after a short wait
INI="$SEISCOMP_ROOT/var/lib/seedlink/seedlink.ini"
if [ ! -s "$INI" ]; then
  /bin/sleep 1 || true
  seiscomp update-config seedlink || true
fi
# restart seedlink so the new plugin block is loaded immediately
seiscomp restart seedlink || true

# ---- Ensure scmaster is up with the new configuration ----
seiscomp start scmaster || true
seiscomp update-config || true
seiscomp restart scmaster || true

# Re-render seedlink after scmaster is up (idempotent) and ensure it is running
seiscomp update-config seedlink || true
seiscomp restart seedlink || true

# ---- FinDer aliases (no overwrite of your preconfigured cfgs) ----
for alias in scfditaly scfdalpine scfdforela; do
    seiscomp alias create "$alias" scfinder || true
done

# Re-copy preconfigured alias configs if available
for alias in scfditaly scfdalpine scfdforela; do
  if [ -f "$USER_SRC/${alias}.cfg" ]; then
    cp -f "$USER_SRC/${alias}.cfg" "$USER_DEST/"
  fi
done

# Override scalert configuration to avoid '+' merge issue
cat > ~/.seiscomp/scalert.cfg <<'EOF'
# Override defaults, avoid '+' merge issue
scripts.event = /opt/seiscomp/etc/runshakemap.sh
EOF

# ---- Region configs (optional: only if you want them copied now) ----
REGIONS="$HOST_SHARED/docker_overrides/shakemap_region_configs"
CONF_HOME="$USER_HOME/shakemap_profiles/default/install/config"
if [ -d "$REGIONS/default" ]; then
  cp -af "$REGIONS/default/." "$CONF_HOME/"
fi
for cc in italy switzerland; do
  if [ -d "$REGIONS/$cc" ]; then
    mkdir -p "$CONF_HOME/$cc"
    cp -af "$REGIONS/$cc/." "$CONF_HOME/$cc/"
  fi
done
# ensure .orig exist (for your restore logic)
for f in gmpe_sets.conf model.conf modules.conf select.conf; do
  if [ -f "$CONF_HOME/$f" ] && [ ! -f "$CONF_HOME/$f.orig" ]; then
    cp "$CONF_HOME/$f" "$CONF_HOME/$f.orig"
  fi
done


# ---- Enable core modules and FinDer aliases, then restart ----
if command -v seiscomp >/dev/null 2>&1; then
  seiscomp enable scgof scalert scevent scfditaly scfdforela scfdalpine || true
  seiscomp restart || true
fi


echo "=== Applying ShakeMap patches as root ==="
PATCH_SRC="/home/sysop/host_shared/docker_overrides/shakemap_patches"
if [ -d "$PATCH_SRC" ]; then
    # SeisComp related patches: ShakeMap trigger python script
    mkdir -p /home/sysop/.seiscomp/scripts/run_events
    cp -f "$PATCH_SRC"/seiscomp_shakemap/*.py "/home/sysop/.seiscomp/scripts/run_events/"
    chown -R sysop:sysop /home/sysop/.seiscomp/scripts/run_events
    chmod +x /home/sysop/.seiscomp/scripts/run_events/*.py

    # Trigger scripts for ShakeMap from scalert. Goes to /opt/seiscomp/etc
    cp -f "$PATCH_SRC"/seiscomp_shakemap/pyshakemap.py "/opt/seiscomp/etc/"
    chmod +x "/opt/seiscomp/etc/pyshakemap.py"
    chown sysop:sysop "/opt/seiscomp/etc/pyshakemap.py"

    cp -f "$PATCH_SRC"/seiscomp_shakemap/runshakemap.sh "/opt/seiscomp/etc/"
    chmod +x "/opt/seiscomp/etc/runshakemap.sh"
    chown sysop:sysop "/opt/seiscomp/etc/runshakemap.sh"

    echo "Patches applied."
else
    echo "WARNING: Patch source folder not found: $PATCH_SRC"
fi

# where the host volume is mounted inside the container
SRC_TGZ="/home/sysop/host_shared/shakemap_config.tgz"
# where ShakeMap expects the profile inside the container
DST_BASE="/home/sysop/shakemap_profiles/default/install"
DST_CFG="${DST_BASE}/config"

if [[ -f "$SRC_TGZ" ]]; then
  echo "[shakemap-config] Installing regional config from $SRC_TGZ"
  mkdir -p "$DST_BASE"

  if [[ -d "$DST_CFG" ]]; then
    # If not backed-up before, back-up
    if [ ! -d "${DST_CFG}.bak" ]; then
      echo "[shakemap-config] Backing up existing config to ${DST_CFG}.bak"
      mv "$DST_CFG" "${DST_CFG}.bak"
    fi
  fi

  tar -xzf "$SRC_TGZ" -C "$DST_BASE"
  chown -R sysop:sysop "$DST_BASE"
  echo "[shakemap-config] Installed to $DST_CFG"
else
  echo "[shakemap-config] Skipped: $SRC_TGZ not found"
fi

# Copy layers
cp shakemap_wkt/*.wkt "$DST_BASE/data/layers/" || true

# Restart scalert to make sure it collected its configuration changes
seiscomp restart scalert || true

echo "=== Post-start setup complete ==="
