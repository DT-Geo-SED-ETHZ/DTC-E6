#!/usr/bin/env bash
# Minimal, robust WF1 playback runner for SeisComP + SeedLink FIFO
# - No direct edits to seedlink.ini or templates
# - Only writes user config (~/.seiscomp/seedlink.cfg)
# - Ensures FIFO exists, (re)renders config, starts SeedLink, waits for FIFO, runs msrtsimul

set -euo pipefail

# ---- Paths ----
PY=python3.9
PLAY=/home/sysop/sc3-playback/playback.py
DB_DEFAULT=/home/sysop/host_shared/seiscomp_db/db.sqlite
MSEED_SORTED=/tmp/sorted_512.mseed
CFG_DIR=/home/sysop/.seiscomp
SEEDLINK_CFG="$CFG_DIR/seedlink.cfg"
FIFO=/opt/seiscomp/var/run/seedlink/mseedfifo
INI=/opt/seiscomp/var/lib/seedlink/seedlink.ini
LOG_SL=/opt/seiscomp/var/log/seedlink.log
KEYDIR=/opt/seiscomp/etc/key/seedlink

# ---- Args ----
RAW_MSEED=${1:-}
INV_SC3ML=${2:-}
DB=${3:-$DB_DEFAULT}

if [ -z "$RAW_MSEED" ]; then
  echo "Usage: $0 <raw.mseed> [inventory.sc3ml] [db.sqlite]" >&2
  exit 2
fi

# ---- Sanity ----
command -v "$PY" >/dev/null || { echo "ERROR: $PY not found" >&2; exit 1; }
[ -r "$RAW_MSEED" ] || { echo "ERROR: raw MiniSEED not found at $RAW_MSEED" >&2; exit 1; }
[ -r "$DB" ]       || { echo "ERROR: DB not found at $DB" >&2; exit 1; }
[ -z "${INV_SC3ML:-}" ] || [ -r "$INV_SC3ML" ] || { echo "ERROR: inventory not readable: $INV_SC3ML" >&2; exit 1; }

cat <<EOF
[run_playback] Using:
  DB   = $DB
  RAW  = $RAW_MSEED
  OUT  = $MSEED_SORTED (fixed 512B)
$( [ -n "${INV_SC3ML:-}" ] && echo "  INV  = $INV_SC3ML" )
EOF

# ---- Stop modules & clean SeedLink buffers ----
/opt/seiscomp/bin/seiscomp stop seedlink scfditaly scfdalpine scfdforela || true
rm -f /opt/seiscomp/var/lib/seedlink/plugin/*            2>/dev/null || true
rm -f /opt/seiscomp/var/lib/seedlink/seedlink.ringbuffer 2>/dev/null || true

# ---- Optional inventory import ----
if [ -n "${INV_SC3ML:-}" ]; then
  echo "[run_playback] Importing inventory: $INV_SC3ML"
  /opt/seiscomp/bin/seiscomp exec import_inv sc3 "$INV_SC3ML" || echo "[run_playback] WARNING: import_inv failed" >&2
fi

# ---- Ensure FIFO path exists ----
mkdir -p "$(dirname "$FIFO")"
if [ ! -p "$FIFO" ]; then
  rm -f "$FIFO" 2>/dev/null || true
  mkfifo "$FIFO"
fi
chmod 666 "$FIFO"

# ---- Ensure SeedLink key bindings (map all stations to 'fifo' profile) ----
mkdir -p "$KEYDIR"
printf '* fifo\n' > "$KEYDIR/profile"
printf 'sources = mseedfifo\n' > "$KEYDIR/profile_fifo"

# ---- Write user SeedLink config (no template hacks) ----
mkdir -p "$CFG_DIR"
[ -f "$SEEDLINK_CFG" ] || : > "$SEEDLINK_CFG"

# msrtsimul = true
if grep -q '^[[:space:]]*msrtsimul[[:space:]]*=' "$SEEDLINK_CFG"; then
  sed -i 's/^[[:space:]]*msrtsimul[[:space:]]*=.*/msrtsimul = true/' "$SEEDLINK_CFG"
else
  printf 'msrtsimul = true\n' >> "$SEEDLINK_CFG"
fi

# Explicit FIFO (some setups read this)
if grep -q '^[[:space:]]*plugins\.mseedfifo\.fifo[[:space:]]*=' "$SEEDLINK_CFG"; then
  sed -i "s|^[[:space:]]*plugins\\.mseedfifo\\.fifo[[:space:]]*=.*|plugins.mseedfifo.fifo = $FIFO|" "$SEEDLINK_CFG"
else
  printf 'plugins.mseedfifo.fifo = %s\n' "$FIFO" >> "$SEEDLINK_CFG"
fi

# Provide fifo_param with required extra args so plugin gets plugin_name
# Template expands: ... -d $plugins.mseedfifo.fifo_param
# We set it to:     <fifo> -n mseedfifo
if grep -q '^[[:space:]]*plugins\.mseedfifo\.fifo_param[[:space:]]*=' "$SEEDLINK_CFG"; then
  sed -i "s|^[[:space:]]*plugins\\.mseedfifo\\.fifo_param[[:space:]]*=.*|plugins.mseedfifo.fifo_param = $FIFO|" "$SEEDLINK_CFG"
else
  printf 'plugins.mseedfifo.fifo_param = %s\n' "$FIFO" >> "$SEEDLINK_CFG"
fi

# ---- Bind profile via SeisComP shell ----
/opt/seiscomp/bin/seiscomp shell <<'EOSH'
set profile seedlink fifo *
exit
EOSH

# ---- Re-render SeedLink config ----
seiscomp update-config || true
seiscomp update-config seedlink || true

# Show rendered plugin line for diagnostics
if [ -f "$INI" ]; then
  echo "[debug] rendered plugin line:" && grep -n '^plugin[[:space:]]\+mseedfifo' "$INI" || echo "[debug] no plugin line"
fi

# ---- Repack MiniSEED to fixed 512B ----
repack_512_obspy() {
  local IN="$1" OUT="$2"
  [ -r "$IN" ] || { echo "ERROR: cannot read $IN" >&2; return 2; }
  "$PY" - <<'PY'
import importlib, sys, subprocess
try:
    importlib.import_module("obspy")
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "obspy"])  # one-time
PY
  "$PY" - "$IN" "$OUT" <<'PY'
from obspy import read
import sys
inp, out = sys.argv[1], sys.argv[2]
st = read(inp)
st.write(out, format="MSEED", encoding="STEIM2", reclen=512)
PY
}

repack_512_obspy "$RAW_MSEED" "/tmp/repack512.mseed"

# Filter to desired SNCLs and ensure fixed 512B records
echo "[run_playback] Repacking to fixed 512B: $MSEED_SORTED"
rm -f "$MSEED_SORTED"
cat /home/sysop/host_shared/my_sncls.txt | /opt/seiscomp/bin/scmssort -vuE -l - "/tmp/repack512.mseed" > "$MSEED_SORTED"
ls -l "$MSEED_SORTED" || true

# ---- Start SeedLink and run playback ----
/opt/seiscomp/bin/seiscomp start seedlink
# Start seiscomp modules
/opt/seiscomp/bin/seiscomp restart scfditaly scfdalpine scfdforela || true

# Playback
seiscomp exec msrtsimul -v $MSEED_SORTED

