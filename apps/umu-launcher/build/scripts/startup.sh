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

# --- Proton -----------------------------------------------------------------
# umu resolves names like "GE-Proton" through api.github.com, which is often
# rate-limited or blocked. Download GE-Proton ourselves from the plain github.com
# release URLs instead, and hand umu a local path. The result is cached in the volume.
PROTON_DIR="${UMU_STATE}/proton"
PROTON_REPO="https://github.com/GloriousEggroll/proton-ge-custom/releases"
PROTON_VERSION="${UMU_PROTON_VERSION:-GE-Proton}"

install_ge_proton() {
    local tag="$1"
    if [ "${tag}" = "GE-Proton" ]; then
        # /releases/latest redirects to /releases/tag/<tag>: no API call needed
        tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${PROTON_REPO}/latest" | sed 's#.*/##')"
        [ -n "${tag}" ] || { gow_log "WARNING: could not resolve latest GE-Proton"; return 1; }
    fi
    if [ ! -d "${PROTON_DIR}/${tag}" ]; then
        gow_log "Downloading ${tag} to ${PROTON_DIR} (first run only)..."
        local tmp ext url ok=0
        tmp="$(mktemp -d)"
        # Release assets have been published as .tar.gz and as .tar.zst
        for ext in tar.zst tar.gz; do
            url="${PROTON_REPO}/download/${tag}/${tag}.${ext}"
            if curl -fSL -o "${tmp}/proton.${ext}" "${url}"; then
                if [ "${ext}" = "tar.zst" ]; then
                    zstd -dc "${tmp}/proton.${ext}" | tar -x -C "${PROTON_DIR}" && ok=1
                else
                    tar -xzf "${tmp}/proton.${ext}" -C "${PROTON_DIR}" && ok=1
                fi
                [ "${ok}" = 1 ] && break
            else
                gow_log "  not available: ${url}"
            fi
        done
        rm -rf "${tmp}"
        if [ "${ok}" != 1 ] || [ ! -d "${PROTON_DIR}/${tag}" ]; then
            rm -rf "${PROTON_DIR}/${tag}"
            gow_log "WARNING: failed to download ${tag}"
            return 1
        fi
    fi
    PROTON_VERSION="${PROTON_DIR}/${tag}"
}

case "${PROTON_VERSION}" in
    GE-Proton*) install_ge_proton "${PROTON_VERSION}" || gow_log "Falling back to umu's own Proton lookup" ;;
esac

# --- umu-launcher environment ----------------------------------------------
export PROTONPATH="${PROTON_VERSION}"
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
