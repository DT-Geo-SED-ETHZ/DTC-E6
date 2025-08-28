# dtgeofinder: SeisComP + FinDer + ShakeMap + PyFinder (Docker)

This repository provides a Dockerized environment to run **SeisComP FinDer**, **ShakeMap**, and **PyFinder** for EEW workflows. It supports fast local testing with waveform **playbacks**, and collects all outputs on the host for easy inspection.

---

## Contents
- [Requirements](#requirements)
- [Quickstart](#quickstart)
- [Build](#build)
- [Run](#run)
- [Mounted Volumes & Outputs](#mounted-volumes--outputs)
- [Playbacks](#playbacks)
  - [WF1: SeisComP Playback](#wf1-seiscomp-playback)
  - [WF2: PyFinder Playback](#wf2-pyfinder-playback)
- [Logs & Debugging](#logs--debugging)
- [Repo Structure](#repo-structure)
- [Troubleshooting](#troubleshooting)
- [Notes & Licensing](#notes--licensing)

---

## Requirements
- **Docker** (Linux/macOS; Windows via WSL2 also works)
- **Git**
- Optional: **GitHub Container Registry** login (`docker login ghcr.io`) if you push/pull private images

Hardware: 
- ≥ 4 CPU cores and ≥ 4 GB RAM recommended for smoother playbacks

---

## Quickstart

```bash
# 1) Clone
git clone https://github.com/DT-Geo-SED-ETHZ/SeisComP-config.git
cd SeisComP-config

# 2) Build the image
./docker_build.sh

# 3) Start the container (post_start_setup must be run manually)
./docker_run.sh

# 4) Run a playback (choose WF1 or WF2 below)
```

---

## Build

Use the helper script; it is **OS-smart**:

```bash
./docker_build.sh
```

- On Apple Silicon (macOS arm64), it automatically uses **buildx** with `--platform linux/amd64`.
- On Linux/x86_64, it uses plain `docker build`.

**Environment overrides** (optional):
- `DOCKERFILE` — Dockerfile path (default: `Dockerfile.dtgeo`)
- `IMAGE_TAG` — Image tag (default: `dtgeofinder:master`)
- `BUILD_CONTEXT` — Build context (default: `.`)
- `FORCE_BUILDX=true` — Force buildx on any system
- `FORCE_PLATFORM=linux/amd64` — Force target platform (implies buildx)

Examples:
```bash
FORCE_PLATFORM=linux/amd64 ./docker_build.sh
IMAGE_TAG=myrepo/dtgeofinder:test DOCKERFILE=Dockerfile.dtgeo ./docker_build.sh
```

---

## Run

Start the container using the run helper:

```bash
./docker_run.sh
```

What it does:
1. Stops/removes any existing `dtgeofinder` container.
2. Prepares host-side output directories under `host_shared/docker-output/`.
3. Ensures a fresh host-side SQLite DB under `host_shared/seiscomp_db/db.sqlite`.
4. Launches the container with all required **volume mappings** and environment settings.

> After the container is started, you must manually run the post-start setup script inside the container:

```bash
docker exec -it dtgeofinder bash
/home/sysop/host_shared/post_start_setup.sh
```

> Make sure your post-start script exists and is executable on the host:
> ```bash
> chmod +x host_shared/post_start_setup.sh
> ```

---

## Mounted Volumes & Outputs

All important paths are mounted back to the **host** so you can inspect results without entering the container:

- **FinDer outputs** → `host_shared/docker-output/FinDer-output/`
- **ShakeMap outputs** → `host_shared/docker-output/shakemap/`
- **PyFinder outputs** → also goes to `host_shared/docker-output/shakemap/` and `host_shared/docker-output/FinDer-output/`
- **SeisComP logs** → `host_shared/.seiscomp_log/`

These directories persist even if you remove the container.

---

## Playbacks

Two playback workflows are supported. Both create outputs on the host (see above) and write logs under `host_shared/.seiscomp_log/`.

### WF1: SeisComP Playback

1. Enter the container and run the helper script:
   ```bash
   docker exec -it dtgeofinder bash
   cd /home/sysop/host_shared/
   bash playback.sh
   ```

   This script will trigger data streaming as if it is in real-time. We have placed sample data and station inventory under `wf1_playback/test1/` for the Mw6.5 Norcia earthquake (https://terremoti.ingv.it/en/event/8863681). The waveforms are a subset of actually avaliable data due to size limitations.

2. **First run note:** SeisComP may hang while initializing its system. If it appears stuck, press `Ctrl+C`, terminate the lingering process, and re-run the script. Subsequent runs should be fine. Also, check `/home/sysop/.seiscomp/log/scfditaly.log`. If you consistently see repeating `too few stations` messages, interrupt the script and re-run.

3. During playback, FinDer and ShakeMap will trigger automatically. There should be products created for 5-60 s after the trigger.
   - Outputs: `host_shared/docker-output/FinDer-output/`, `host_shared/docker-output/shakemap/`
   - Logs: `host_shared/.seiscomp_log/`

### WF2: PyFinder Playback

1. Enter the container and run PyFinder’s playback with **Python 3.9**:
   ```bash
   docker exec -it dtgeofinder bash
   cd /home/sysop/pyfinder/pyfinder
   python3.9 playback.py --event-id 20161030_0000029
   ```

   > **Note:** PyFinder follows RRSM update schedule from 5 minutes to 48 hours after an earthquake. If you wait long enough, it will submit all pre-scheduled update times into the database and follow them up. This does not change the final outcome since the playback emulates real-time data flow. Otherwise, feel free to break the process with `CTRL+C` after first iteration is completed. If you don't use `--event-id`, PyFinder will submit jobs for all predefined events in `playback.py`.

2. Outputs appear in `host_shared/docker-output/shakemap/` and `host_shared/docker-output/PyFinder-output`. You can tell apart PyFinder shakemap solutions by its name `<event-id><scheduled iteration>`, e.g. `20161030_0000029_t00000`
Output files and SeisComp logs can be collected from the host side from the mounted volumes. No need to copy from the container.

---

## Logs & Debugging

- All runtime SeisComp logs are under:
  ```
  host_shared/.seiscomp_log/
  ```
- Tail a log in real time:
  ```bash
  docker exec -it dtgeofinder bash -lc "tail -n 200 -f /home/sysop/.seiscomp/log/scfditaly.log"
  ```
- Restart a SeisComP module inside the container:
  ```bash
  docker exec -it dtgeofinder bash -lc "/opt/seiscomp/bin/seiscomp restart <module>"
  ```
- If you interrupted a script and left zombies, the container is always started fresh when use `docker_run.sh`, but you can also clean up manually inside the container:
  ```bash
  pkill -f spawn_main || true
  ```

---

## Repo Structure

```
SeisComP-config/
├─ Dockerfile.dtgeo                  # Image build (SeisComP + FinDer + ShakeMap + PyFinder)
├─ docker_build.sh                   # OS-smart build helper (buildx on Apple Silicon)
├─ docker_run.sh                     # Start helper; sets up volumes and starts container
├─ host_shared/
│  ├─ playback.sh                    # WF1 helper (SeisComP playback)
│  ├─ post_start_setup.sh            # Manual post-start setup script (run inside container after start)
│  ├─ docker-output/
│  │  ├─ FinDer-output/              # FinDer results (host)
│  │  ├─ shakemap/                   # ShakeMap results (host)
│  │  └─ PyFinder-output/            # PyFinder results (host)
│  └─ docker_overrides/
│     └─ shakemap_patches/           # Local ShakeMap patches (copied during build)
└─ README.md                         # This file
```

---

## Notes & Licensing

- **FinDer** is **not open-source**. The image includes it for internal evaluation; do not redistribute binaries.
- See [LICENSE](./LICENSE) and [DISCLAIMER](./DISCLAIMER.md) for terms and exceptions.

