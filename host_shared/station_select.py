#!/usr/bin/env python3
"""
filter_sncls_by_distance.py

Usage
-----
python filter_sncls_by_distance.py \
  --inventory path/to/inventory.xml \
  --lat 37.123 --lon 35.456 \
  --radius-km 150 \
  --out sncls.txt \
  [--chan-regex '^(HH|BH)..$'] \
  [--active-at '2025-08-20T12:34:56']

Notes
-----
- Inventory must be FDSN StationXML (export via scxmldump or fdsnws-station).
- Each output line: NET.STA.LOC.CHA
- Optional filters:
    * --chan-regex    : keep only channels matching this regex
    * --active-at     : keep only channels/stations active at this ISO time
"""
import argparse
import math
import re
from datetime import datetime, timezone

try:
    from obspy import read_inventory
except ImportError as e:
    raise SystemExit("ObsPy is required. Install with: pip install obspy") from e


def haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance in km (Haversine)."""
    R = 6371.0088  # mean Earth radius [km]
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = phi2 - phi1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(a))


def in_time_window(start, end, when):
    """Return True if 'when' is within [start, end] (end may be None = open)."""
    if when is None:
        return True
    if start and when < start:
        return False
    if end and when > end:
        return False
    return True


def main():
    ap = argparse.ArgumentParser(description="Filter SNCLs within X km of an epicenter.")
    ap.add_argument("--inventory", required=True, help="FDSN StationXML file")
    ap.add_argument("--lat", type=float, required=True, help="Epicenter latitude")
    ap.add_argument("--lon", type=float, required=True, help="Epicenter longitude")
    ap.add_argument("--radius-km", type=float, required=True, help="Radius in km")
    ap.add_argument("--out", required=True, help="Output file for SNCL list")
    ap.add_argument("--chan-regex", default=None, help="Regex for channel code filter (e.g. '^(HH|BH)..$')")
    ap.add_argument("--active-at", default=None, help="ISO time to require channel active (e.g. 2025-08-20T12:34:56)")
    args = ap.parse_args()

    inv = read_inventory(args.inventory, format="SC3ML")

    chan_re = re.compile(args.chan_regex) if args.chan_regex else None
    when = None
    if args.active_at:
        # Make timezone-aware UTC if no tz provided
        try:
            when = datetime.fromisoformat(args.active_at)
        except ValueError:
            raise SystemExit("Could not parse --active-at. Use ISO like 2025-08-20T12:34:56")
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)

    sncls = set()
    kept_stations = set()

    for net in inv:
        for sta in net:
            # Station-level distance check
            if sta.latitude is None or sta.longitude is None:
                continue
            dist_km = haversine_km(args.lat, args.lon, sta.latitude, sta.longitude)
            if dist_km > args.radius_km:
                continue

            # Optional station activity time check
            if when is not None:
                sta_start = sta.start_date
                sta_end = sta.end_date
                if sta_start and sta_start.tzinfo is None:
                    sta_start = sta_start.replace(tzinfo=timezone.utc)
                if sta_end and sta_end.tzinfo is None:
                    sta_end = sta_end.replace(tzinfo=timezone.utc)
                if not in_time_window(sta_start, sta_end, when):
                    continue

            kept_stations.add((net.code, sta.code))

            # Channel-level selection
            for cha in sta.channels:
                if chan_re and not chan_re.match(cha.code):
                    continue

                # Optional channel activity window
                if when is not None:
                    cha_start = cha.start_date
                    cha_end = cha.end_date
                    if cha_start and cha_start.tzinfo is None:
                        cha_start = cha_start.replace(tzinfo=timezone.utc)
                    if cha_end and cha_end.tzinfo is None:
                        cha_end = cha_end.replace(tzinfo=timezone.utc)
                    if not in_time_window(cha_start, cha_end, when):
                        continue

                loc = cha.location_code or ""
                sncls.add(f"{net.code}.{sta.code}.{loc}.{cha.code}")

    with open(args.out, "w", encoding="utf-8") as f:
        for sncl in sorted(sncls):
            f.write(sncl + "\n")

    print(f"Wrote {len(sncls)} SNCLs to {args.out}")
    if kept_stations:
        print(f"Stations kept: {len(kept_stations)}")


if __name__ == "__main__":
    main()
    