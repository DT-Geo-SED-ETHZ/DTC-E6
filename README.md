

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

# 3) Start the container (runs post_start_setup automatically)
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
5. **Automatically runs** `post_start_setup.sh` inside the container (if present & executable) and then keeps the container alive (`tail -f /dev/null`).

> Make sure your post-start script exists and is executable on the host:
> ```bash
> chmod +x host_shared/post_start_setup.sh
> ```

---

## Mounted Volumes & Outputs

All important paths are mounted back to the **host** so you can inspect results without entering the container:

- **FinDer outputs** → `host_shared/docker-output/FinDer-output/`
- **ShakeMap outputs** → `host_shared/docker-output/shakemap/`
- **PyFinder outputs** → `host_shared/docker-output/PyFinder-output/`
- **SeisComP logs** → `host_shared/.seiscomp_log/`

These directories persist even if you remove the container.

---

## Playbacks

Two playback workflows are supported. Both create outputs on the host (see above) and write logs under `host_shared/.seiscomp_log/`.

### WF1: SeisComP Playback

1. Enter the container and run the helper script:
   ```bash
   docker exec -it dtgeofinder bash
   /home/sysop/host_shared/playback.bash
   ```

2. **First run note:** SeisComP may hang while initializing its system. If it appears stuck, press `Ctrl+C`, terminate the lingering process, and re-run the script. Subsequent runs should be fine.

3. During playback, FinDer and ShakeMap will trigger automatically.
   - Outputs: `host_shared/docker-output/FinDer-output/`, `host_shared/docker-output/shakemap/`
   - Logs: `host_shared/.seiscomp_log/`

### WF2: PyFinder Playback

1. Enter the container and run PyFinder’s playback with **Python 3.9**:
   ```bash
   docker exec -it dtgeofinder bash
   cd /home/sysop/pyfinder/pyfinder
   python3.9 playback.py
   ```

   > **Note:** If you wait long enough, PyFinder will submit all pre-scheduled update times into the database and follow them up. This does not change the final outcome since the playback emulates real-time data flow. Otherwise, feel free to break the process with `CTRL+C`

2. Outputs appear in `host_shared/docker-output/shakemap/`.

---

## Logs & Debugging

- All runtime logs (SeisComP, FinDer, ShakeMap) are under:
  ```
  host_shared/.seiscomp_log/
  ```
- Tail a log in real time:
  ```bash
  docker exec -it dtgeofinder bash -lc "tail -n 200 -f /home/sysop/.seiscomp/log/finder.log"
  ```
- Restart a SeisComP module inside the container:
  ```bash
  docker exec -it dtgeofinder bash -lc "seiscomp restart <module>"
  ```
- If you interrupted a script and left zombies, the container uses `--init`, but you can also clean up manually inside the container:
  ```bash
  pkill -f spawn_main || true
  ```

---

## Repo Structure

```
SeisComP-config/
├─ Dockerfile.dtgeo                  # Image build (SeisComP + FinDer + ShakeMap + PyFinder)
├─ docker_build.sh                   # OS-smart build helper (buildx on Apple Silicon)
├─ docker_run.sh                     # Start helper; runs post_start_setup and sets up volumes
├─ host_shared/
│  ├─ playback.bash                  # WF1 helper (SeisComP playback)
│  ├─ post_start_setup.sh            # Runs automatically at container start (via docker_run)
│  ├─ docker-output/
│  │  ├─ FinDer-output/              # FinDer results (host)
│  │  ├─ shakemap/                   # ShakeMap results (host)
│  │  └─ PyFinder-output/            # PyFinder results (host)
│  └─ docker_overrides/
│     └─ shakemap_patches/           # Local ShakeMap patches (copied during build)
└─ README.md                         # This file
```

---

## Troubleshooting

- **PR page slow / GitHub UI lag**: try private window, disable extensions, or use another browser.
- **Cannot push due to large files**: remove large binaries from history or use Git LFS.
- **Shakemap/STREC database paths**: the build ensures both `~/.strec/moment_tensors.db` and `~/sm_data/moment_tensors.db` are present. If you override paths, make sure both exist when required.
- **Post-start script did not run**: ensure it exists and is executable at `host_shared/post_start_setup.sh`. The run script calls it automatically.
- **No outputs**: confirm playback actually ran; check logs in `host_shared/.seiscomp_log/`.

---

## Notes & Licensing

- **FinDer** is **not open-source**. The image includes it for internal evaluation; do not redistribute binaries.
- Outputs are always collected on the host via mounted volumes for reproducibility and archival.

If you have questions or improvements, open an issue or PR.