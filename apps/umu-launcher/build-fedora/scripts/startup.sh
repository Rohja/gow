#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

# --- Validate configuration -------------------------------------------------
if [ -z "${UMU_APP_EXE:-}" ]; then
    gow_log "ERROR: UMU_APP_EXE is not set (name of the .exe to run, relative to /app)"
    exit 1
fi

APP_DIR=/app
if [ ! -f "${APP_DIR}/${UMU_APP_EXE}" ]; then
    gow_log "ERROR: '${APP_DIR}/${UMU_APP_EXE}' not found. Is the host folder mounted on /app? Contents of ${APP_DIR}:"
    ls -la "${APP_DIR}" 2>&1 | while read -r l; do gow_log "  $l"; done
    exit 1
fi

# --- Persistent storage (Proton, runtime, wine prefix) ----------------------
UMU_STATE=/var/umu
mkdir -p "${UMU_STATE}"/{proton,prefix,umu-data} "$HOME/.local/share/Steam"
ln -sfn "${UMU_STATE}/umu-data" "$HOME/.local/share/umu"
ln -sfn "${UMU_STATE}/proton" "$HOME/.local/share/Steam/compatibilitytools.d"

# --- umu-launcher environment ----------------------------------------------
# GE-Proton (latest) is downloaded automatically on first run and cached in the volume.
export PROTONPATH="${UMU_PROTON_VERSION:-GE-Proton}"
export WINEPREFIX="${UMU_STATE}/prefix"
export GAMEID="${UMU_GAME_ID:-umu-default}"
export STORE="${STORE:-none}"

# Optional arguments, split on whitespace
ARGS=()
if [ -n "${UMU_APP_ARGS:-}" ]; then
    read -ra ARGS <<< "${UMU_APP_ARGS}"
fi

if [ -n "${UMU_APP_WORKDIR:-}" ]; then
    cd "${APP_DIR}/${UMU_APP_WORKDIR}"
else
    cd "$(dirname "${APP_DIR}/${UMU_APP_EXE}")"
fi

source /opt/gow/launch-comp.sh
[ -z "$RUN_GAMESCOPE" ] && [ -z "$RUN_SWAY" ] && export RUN_GAMESCOPE=1

gow_log "Launching ${UMU_APP_EXE} with PROTONPATH=${PROTONPATH} GAMEID=${GAMEID}"
launcher umu-run "${APP_DIR}/${UMU_APP_EXE}" "${ARGS[@]}"
