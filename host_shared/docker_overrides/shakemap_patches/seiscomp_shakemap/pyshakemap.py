#!/usr/bin/env python3

import subprocess
from concurrent.futures import ThreadPoolExecutor
import time
import os
from datetime import datetime
import tempfile
import psutil
import logging
import sys
import logging

USER = "scalert"
PYTHON_EXEC = "/home/sysop/miniconda/bin/python"
SHAKEMAP_SCRIPT = "/home/sysop/.seiscomp/scripts/run_events/make_rupturejson_and_allxmlinput_fromdb_call_shake.py"
LOGFILE = os.path.expanduser(f"~/.seiscomp/log/{USER}-processing-info.log")
LOGFILE_PY = os.path.expanduser(f"~/.seiscomp/log/{USER}-pyshakemap.log")
START_TIME = time.time()

logger = logging.getLogger("pyshakemap")
logger.setLevel(logging.DEBUG)

# Create a set to keep track of already processed events
# to avoid multiple shakemap calls in case SeisComp triggers 
# this script multiple times for the same event_id.
already_processed_events = set()

if not logger.handlers:
    handler = logging.FileHandler(LOGFILE_PY)
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if not logger or not logger.handlers:
        print(f"[{timestamp}] {message}", flush=True)
    else:
        logger.debug(message)


def is_shakemap_running(event_id):
    for proc in psutil.process_iter(['cmdline']):
        try:
            cmd = proc.info['cmdline']
            if cmd and any(event_id in arg for arg in cmd):
                if SHAKEMAP_SCRIPT in cmd:
                    return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return False

def run_delayed(event_id, delay, original_event_id):
    try:
        # Fake event_id so that shakemap can run in parallel
        # for the same event at different delay times.
        delayed_event_id = f"{event_id}_{delay}"

        # Check if the event has already being processed. If yes, skip it.
        # If not, add it to the set of already processed events and go on.
        if delayed_event_id in already_processed_events:
            log(f"Event {delayed_event_id} has already been processed. Skipping.")
            return
        already_processed_events.add(delayed_event_id)

        # Check if the event was processed before
        flag_dir = os.path.join(tempfile.gettempdir(), "pyshakemap_flags")
        os.makedirs(flag_dir, exist_ok=True)
        flag_path = os.path.join(flag_dir, f"{delayed_event_id}.flag")

        if os.path.exists(flag_path):
            log(f"Event {delayed_event_id} has already been processed. Skipping.")
            return
        else:
            with open(flag_path, 'w') as f:
                f.write("processed")
        log(f"Event {delayed_event_id} is being processed.")

        # Actual sleep time calculation from the start time
        now = time.time()
        target_time = START_TIME + delay
        wait_time = max(0, target_time - now)
        log(f"Waiting {wait_time:.2f}s for the scheduled time for event {event_id} with delay {delay}s")
        time.sleep(wait_time)

        log(f"Running ShakeMap for event {event_id} with delay {delay}s")
        log(f"Calling scxmldump for event {original_event_id}...")
        result = subprocess.run(
            ["scxmldump", "-E", original_event_id, "-f"],
            capture_output=True,
            text=True,
            check=True
        )
        log(f"scxmldump executed...")
        for line in result.stdout.splitlines():
            if "<preferredOriginID>" in line:
                orgid = line.split(">")[1].split("<")[0]
                break
        else:
            log(f"Could not find preferredOriginID for {original_event_id}")
            return

        log(f"Running ShakeMap for origin {orgid}, event_id {delayed_event_id}")
        cmd = [
            "seiscomp", "exec", PYTHON_EXEC,
            SHAKEMAP_SCRIPT,
            "--origin_id", orgid,
            "--event_id", delayed_event_id,
            "--shakemap_flag", "True"
        ]
        try:
            result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            log(f"ShakeMap stdout:\n{result.stdout}")
            log(f"ShakeMap stderr:\n{result.stderr}")
        except subprocess.CalledProcessError as e:
            log(f"[ERROR] ShakeMap call failed for {delayed_event_id}: {e}")
            log(f"stdout:\n{e.stdout}")
            log(f"stderr:\n{e.stderr}")
            return
        
    except Exception as e:
        log(f"[EXCEPTION in delay {delay}] {type(e).__name__}: {e}")


def main(event_id, original_event_id):
    delays = [5, 10, 20, 30, 40, 50, 60]
    log(f"Using ThreadPoolExecutor with max_workers=2")

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = []
        for delay in delays:
            futures.append(executor.submit(run_delayed, event_id, delay, original_event_id))
            log(f"Scheduled thread for delay {delay}s")
            time.sleep(1)  # Optional staggering of submission

        for delay, future in zip(delays, futures):
            try:
                future.result()
                log(f"Thread for delay {delay}s has completed.")
            except Exception as e:
                log(f"[EXCEPTION in thread for delay {delay}] {type(e).__name__}: {e}")

    log("All ShakeMap runs have completed. Exiting script.")

if __name__ == "__main__":
    print("Starting ShakeMap processing script...")
    
    if len(sys.argv) < 2:
        print("Usage: python3 pyshakemaps.py <EventID>")
        sys.exit(1)

    EVENT_ID = sys.argv[3]
    ORIGINAL_EVENT_ID = EVENT_ID  # unless we want to pass a separate value
    main(EVENT_ID, ORIGINAL_EVENT_ID)

    # # Prevent main thread from exiting immediately
    # while threading.active_count() > 1:
    #     time.sleep(1)