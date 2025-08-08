#!/usr/bin/env bash
set -e #uo pipefail

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
if [ -f "$USER_DEST/global.cfg" ]; then
  if grep -q "dbPlugin" "$USER_DEST/global.cfg"; then
    sed -i 's|^\s*dbPlugin\s*=.*|dbPlugin = dbsqlite3|' "$USER_DEST/global.cfg"
  else
    echo "dbPlugin = dbsqlite3" >> "$USER_DEST/global.cfg"
  fi
  if grep -q "^\s*database\s*=" "$USER_DEST/global.cfg"; then
    sed -i "s|^\s*database\s*=.*|database = ${DB_URI}|" "$USER_DEST/global.cfg"
  else
    echo "database = ${DB_URI}" >> "$USER_DEST/global.cfg"
  fi

  # Ensure core.plugins includes dbsqlite3 (required by some versions)
  if grep -q "^\s*core\.plugins" "$USER_DEST/global.cfg"; then
    if ! grep -q "core\.plugins.*dbsqlite3" "$USER_DEST/global.cfg"; then
      sed -i 's|^\s*core\.plugins\s*=.*|core.plugins = dbsqlite3|' "$USER_DEST/global.cfg"
    fi
  else
    echo "core.plugins = dbsqlite3" >> "$USER_DEST/global.cfg"
  fi
fi

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
fi

# ---- Ensure scmaster is up with the new configuration ----
seiscomp start scmaster || true
/bin/sleep 2 || true
seiscomp update-config || true
seiscomp restart scmaster || true

# ---- Seedlink FIFO profile cheatcode (if desired) ----
PROFILE_KEY="$SEISCOMP_ROOT/etc/key/seedlink/profile_fifo"
mkdir -p "$(dirname "$PROFILE_KEY")"
echo "sources = seedlink:mseedfifo" > "$PROFILE_KEY"
printf "set profile seedlink fifo *.*\nexit\n" | seiscomp shell || true

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
  seiscomp enable scgof scalert scevent scwfparam scfditaly scfdforela scfdalpine || true
  seiscomp restart || true
fi

echo "=== Post-start setup complete ==="
