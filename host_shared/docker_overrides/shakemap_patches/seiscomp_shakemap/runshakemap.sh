#!/bin/bash

# Wrapper for running the Python-based delayed ShakeMap scheduler
# This script is meant to be triggered by SeisComP (e.g., scalert)

# Arguments:
# $1: Message string (optional, can be ignored or logged)
# $2: Event flag (1 = new, 0 = update)
# $3: Event ID (required)
# $4: Arrival count (optional)
# $5: Magnitude (optional)

PYTHON="python3.9"
SCRIPT="/opt/seiscomp/etc/pyshakemap.py"

LOGFILE="$HOME/.seiscomp/log/scalert-pyshakemap.log"
echo "[INFO] runshakemap.sh was called at $(date)" >> "$LOGFILE"
echo "[INFO] Triggering delayed ShakeMap Python module with args: $@" >> "$LOGFILE"

# Capture all Python output to the same file
# "$PYTHON" "$SCRIPT" "$@" >> "$LOGFILE" 2>&1 &
# disown
# exit 0

setsid -f "$PYTHON" "$SCRIPT" "$@" >>"$LOGFILE" 2>&1
