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

# Download and extract one release tag. Asset names are read from the release page
# (plain HTML, no API) because they vary between releases (.tar.gz / .tar.zst).
download_ge_proton_tag() {
    local tag="$1" tmp url urls ok=1
    [ -d "${PROTON_DIR}/${tag}" ] && return 0
    urls="$(curl -fsSL "${PROTON_REPO}/expanded_assets/${tag}" 2>/dev/null |
            grep -oE "/GloriousEggroll/proton-ge-custom/releases/download/[^\"]+\.tar\.(zst|gz)" |
            sed 's#^#https://github.com#' | sort -u || true)"
    # Fallback: the conventional names
    urls="${urls:-${PROTON_REPO}/download/${tag}/${tag}.tar.gz ${PROTON_REPO}/download/${tag}/${tag}.tar.zst}"
    gow_log "Downloading ${tag} to ${PROTON_DIR} (first run only)..."
    tmp="$(mktemp -d)"
    for url in ${urls}; do
        gow_log "  trying ${url}"
        if curl -fSL -o "${tmp}/proton.tar" "${url}"; then
            case "${url}" in
                *.zst) zstd -dc "${tmp}/proton.tar" | tar -x -C "${PROTON_DIR}" ;;
                *)     tar -xzf "${tmp}/proton.tar" -C "${PROTON_DIR}" ;;
            esac && [ -d "${PROTON_DIR}/${tag}" ] && { ok=0; break; }
        fi
    done
    rm -rf "${tmp}"
    [ "${ok}" = 0 ] || rm -rf "${PROTON_DIR}/${tag}"
    return "${ok}"
}

install_ge_proton() {
    local wanted="$1" tags tag
    if [ "${wanted}" = "GE-Proton" ]; then
        # No API: the "latest" redirect, then the releases feed for older candidates
        tags="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${PROTON_REPO}/latest" | sed 's#.*/##')"
        tags="${tags} $(curl -fsSL "${PROTON_REPO}.atom" 2>/dev/null |
                        grep -oE '/releases/tag/GE-Proton[^"<]+' | sed 's#.*/##' | head -n 5 || true)"
        gow_log "GE-Proton release candidates: ${tags}"
    else
        tags="${wanted}"
    fi
    local seen=" "
    for tag in ${tags}; do
        case "${seen}" in *" ${tag} "*) continue ;; esac
        seen="${seen}${tag} "
        if download_ge_proton_tag "${tag}"; then
            PROTON_VERSION="${PROTON_DIR}/${tag}"
            return 0
        fi
        gow_log "WARNING: no usable download for ${tag}"
    done
    return 1
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
