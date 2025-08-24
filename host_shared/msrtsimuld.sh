#!/usr/bin/env bash
# Run historic playback using sc3-playback, with module stop/clean prep
set -euo pipefail

# ---- Paths ----
PY=python3.9
PLAY=/home/sysop/sc3-playback/playback.py
DB_DEFAULT=/home/sysop/host_shared/seiscomp_db/db.sqlite
MSEED_SORTED=/tmp/sorted_512.mseed
CFG=/home/sysop/.seiscomp
FIFO=/opt/seiscomp/var/run/seedlink/mseedfifo


# ---- Arguments ----
# Usage: run_playback.sh <raw.mseed> [inventory.sc3ml] [db.sqlite]
RAW_MSEED=${1:-}
INV_SC3ML=${2:-}
DB=${3:-$DB_DEFAULT}

if [ -z "$RAW_MSEED" ]; then
  echo "Usage: $0 <raw.mseed> [inventory.sc3ml] [db.sqlite]" >&2
  exit 2
fi


# ---- Sanity checks ----
command -v "$PY" >/dev/null || { echo "ERROR: $PY not found" >&2; exit 1; }
[ -r "$PLAY" ] || { echo "ERROR: playback.py not found at $PLAY" >&2; exit 1; }
[ -r "$DB" ]   || { echo "ERROR: DB not found at $DB" >&2; exit 1; }
[ -r "$RAW_MSEED" ] || { echo "ERROR: raw MiniSEED not found at $RAW_MSEED" >&2; exit 1; }

echo "[run_playback] Using:"
echo "  DB   = $DB"
echo "  RAW  = $RAW_MSEED"
echo "  OUT  = $MSEED_SORTED (fixed 512B)"
[ -n "$INV_SC3ML" ] && echo "  INV  = $INV_SC3ML" || true
echo

# ---- Stop modules and clean SeedLink buffers ----
/opt/seiscomp/bin/seiscomp stop scfditaly scfdalpine scfdforela seedlink || true

# wipe ringbuffer / plugin queues so we start fresh
rm -f /opt/seiscomp/var/lib/seedlink/plugin/*            2>/dev/null || true
rm -f /opt/seiscomp/var/lib/seedlink/seedlink.ringbuffer 2>/dev/null || true

# ---- Optional: import inventory (SC3ML) so stations exist ----
if [ -n "$INV_SC3ML" ]; then
  echo "[run_playback] Importing inventory: $INV_SC3ML"
  /opt/seiscomp/bin/seiscomp exec import_inv sc3 "$INV_SC3ML" || {
    echo "[run_playback] WARNING: import_inv failed for $INV_SC3ML" >&2
  }
fi

# ---- Ensure SeedLink mseedfifo bindings/profile exist (avoid "no plugins defined") ----
SEISCOMP=/opt/seiscomp
KEYDIR="$SEISCOMP/etc/key/seedlink"
mkdir -p "$KEYDIR"
# Map all stations to the 'fifo' profile
printf '* fifo\n' > "$KEYDIR/profile"
# Define the 'fifo' profile to use mseedfifo sources
printf 'sources = mseedfifo\n' > "$KEYDIR/profile_fifo"

# Also set SeedLink CFG in the **user** scope so it takes precedence
SEEDLINK_CFG="$HOME/.seiscomp/seedlink.cfg"
mkdir -p "$(dirname "$SEEDLINK_CFG")"
# Create file if missing but DO NOT wipe existing content
[ -f "$SEEDLINK_CFG" ] || : > "$SEEDLINK_CFG"

# Ensure: msrtsimul = true  (replace if present, append if missing)
if grep -q '^[[:space:]]*msrtsimul[[:space:]]*=' "$SEEDLINK_CFG"; then
  sed -i 's/^[[:space:]]*msrtsimul[[:space:]]*=.*/msrtsimul = true/' "$SEEDLINK_CFG"
else
  printf 'msrtsimul = true\n' >> "$SEEDLINK_CFG"
fi

# Ensure: plugins.mseedfifo.fifo = $FIFO  (replace if present, append if missing)
if grep -q '^[[:space:]]*plugins\.mseedfifo\.fifo[[:space:]]*=' "$SEEDLINK_CFG"; then
  sed -i "s|^[[:space:]]*plugins\\.mseedfifo\\.fifo[[:space:]]*=.*|plugins.mseedfifo.fifo = $FIFO|" "$SEEDLINK_CFG"
else
  printf 'plugins.mseedfifo.fifo = %s\n' "$FIFO" >> "$SEEDLINK_CFG"
fi

# Ensure binding mapping via seiscomp shell (same as repo logic)
/opt/seiscomp/bin/seiscomp shell <<'EOSH'
set profile seedlink fifo *
exit
EOSH

/opt/seiscomp/bin/seiscomp update-config || true
/opt/seiscomp/bin/seiscomp update-config seedlink || true

# ---- Idempotent render + verify seedlink.ini (avoid "needs to run twice") ----
INI="/opt/seiscomp/var/lib/seedlink/seedlink.ini"
for i in 1 2; do
  if [ -s "$INI" ] && grep -q '^plugin[[:space:]]\+mseedfifo' "$INI" 2>/dev/null && \
     grep -q "^[[:space:]]*fifo[[:space:]]*=\s*$FIFO" "$INI" 2>/dev/null; then
    echo "[run_playback] seedlink.ini ok (mseedfifo + fifo=$FIFO)"
    break
  fi
  echo "[run_playback] seedlink.ini missing/incomplete; re-rendering ($i)"
  /opt/seiscomp/bin/seiscomp update-config seedlink || true
  # sleep -s 1
done

if ! [ -s "$INI" ] || ! grep -q '^plugin[[:space:]]\+mseedfifo' "$INI" 2>/dev/null; then
  echo "[run_playback] ERROR: seedlink.ini not rendered with mseedfifo" >&2
  sed -n '1,160p' "$INI" 2>/dev/null || true
  exit 5
fi

# Prime SeedLink once so paths/buffers exist, then stop; playback.py will (re)start it
/opt/seiscomp/bin/seiscomp start seedlink || true
# sleep -s 1
/opt/seiscomp/bin/seiscomp stop seedlink || true


# Repack MiniSEED to fixed 512-byte records using ObsPy (decodes/re-encodes).
repack_512_obspy() {
  local IN="$1" OUT="$2"
  [ -r "$IN" ] || { echo "ERROR: cannot read $IN" >&2; return 2; }

  # Ensure obspy is available (one-time install to user site)
  python3.9 - <<'PY'
import importlib, sys, subprocess
try:
    importlib.import_module("obspy")
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "obspy"])
PY

  python3.9 - <<'PY' "$IN" "$OUT"
from obspy import read
import sys
inp, out = sys.argv[1], sys.argv[2]
st = read(inp)
st.write(out, format="MSEED", encoding="STEIM2", reclen=512)
PY

  # verify: first few records must report size=512
  /opt/seiscomp/bin/seiscomp-python - <<'PY' "$OUT"
from seiscomp import mseedlite as m
import sys
ok=True
with open(sys.argv[1],'rb') as f:
    for i,rec in enumerate(m.Input(f)):
        print("size:", rec.size)
        if rec.size != 512: ok=False
        if i>=9: break
print("VERIFY_512:", "OK" if ok else "FAIL")
PY
}
repack_512_obspy "$RAW_MSEED" "/tmp/repack512.mseed" || {
  echo "[run_playback] ERROR: repack to fixed 512B failed" >&2
  exit 3
}

# Now repack to fixed 512-byte records for SeedLink
echo "[run_playback] Repacking to fixed 512B: $MSEED_SORTED"
# remove any old output so we don’t accidentally reuse it
rm -f "$MSEED_SORTED"
# /opt/seiscomp/bin/scmssort -vuE "/tmp/repack512.mseed" > "$MSEED_SORTED"
# echo IV.MM01.*.* | /opt/seiscomp/bin/scmssort -vuE -l - "/tmp/repack512.mseed" > "$MSEED_SORTED"
cat /home/sysop/host_shared/my_sncls.txt | /opt/seiscomp/bin/scmssort -vuE -l - "/tmp/repack512.mseed" > "$MSEED_SORTED"

ls -l "$MSEED_SORTED" || true

# ---- Ensure FIFO exists (mseedfifo plugin expects this path) ----
mkdir -p "$(dirname "$FIFO")"
if [ ! -p "$FIFO" ]; then
  rm -f "$FIFO" 2>/dev/null || true
  mkfifo "$FIFO"
  chmod 666 "$FIFO"
fi

seiscomp enable seedlink
seiscomp start scmaster 
seiscomp restart seedlink
# ---- Kick off playback (Python tool will handle starting modules) ----
echo "[run_playback] Launching Python playback..."
seiscomp restart seedlink scfditaly scfdalpine scfdforela || true
seiscomp exec msrtsimul -v "$MSEED_SORTED" 
# exec "$PY" "$PLAY" "$DB" "$MSEED_SORTED" -c /home/sysop/.seiscomp # --mode historic
# exec "$PY" "$PLAY" "$DB" "/tmp/smallsmall.mseed" -c /home/sysop/.seiscomp --mode historic