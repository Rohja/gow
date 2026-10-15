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

# Latest GE-Proton tag, from the /releases/latest redirect (no API call).
resolve_latest_ge_proton() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' "${PROTON_REPO}/latest" | sed 's#.*/##'
}

# Download and extract the build of release <tag> matching this machine's architecture.
# Asset names are read from the release page (plain HTML, no API), e.g.
# GE-Proton11-9-x86_64.tar.gz / GE-Proton11-9-aarch64.tar.gz
install_ge_proton() {
    local tag="$1" arch assets url tmp top
    arch="$(uname -m)"
    [ -d "${PROTON_DIR}/${tag}" ] && return 0

    assets="$(curl -fsSL "${PROTON_REPO}/expanded_assets/${tag}" |
              grep -oE "/GloriousEggroll/proton-ge-custom/releases/download/[^\"]+\.tar\.(zst|gz)" || true)"
    url="$(printf '%s\n' "${assets}" | grep -E -- "-${arch}\.tar\.(zst|gz)$" | head -n1 || true)"
    if [ -z "${url}" ] && [ "${arch}" = "x86_64" ]; then
        # Older releases ship a single, arch-less (x86_64) archive
        url="$(printf '%s\n' "${assets}" | grep -vE -- '-(aarch64|x86_64)\.tar' | head -n1 || true)"
    fi
    if [ -z "${url}" ]; then
        gow_log "ERROR: no ${arch} archive found for ${tag} (${PROTON_REPO}/tag/${tag})"
        return 1
    fi
    url="https://github.com${url}"

    gow_log "Downloading ${tag} (${arch}) from ${url} (first run only)..."
    tmp="$(mktemp -d -p "${PROTON_DIR}" .download.XXXXXX)"
    if ! curl -fsSL -o "${tmp}/proton.tar" "${url}"; then
        gow_log "ERROR: failed to download ${url}"
        rm -rf "${tmp}"; return 1
    fi
    mkdir "${tmp}/x"
    case "${url}" in
        *.zst) zstd -dc "${tmp}/proton.tar" | tar -x -C "${tmp}/x" ;;
        *)     tar -xzf "${tmp}/proton.tar" -C "${tmp}/x" ;;
    esac || { gow_log "ERROR: failed to extract ${url}"; rm -rf "${tmp}"; return 1; }

    # The top-level folder name is not guaranteed to match the tag: normalise it
    top="$(find "${tmp}/x" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "${top}" ] || [ ! -e "${top}/proton" ]; then
        gow_log "ERROR: ${url} does not contain a Proton build"
        rm -rf "${tmp}"; return 1
    fi
    mv "${top}" "${PROTON_DIR}/${tag}"
    rm -rf "${tmp}"
}

case "${PROTON_VERSION}" in
    GE-Proton*)
        # Only the requested (or latest) version is tried: any failure is fatal
        tag="${PROTON_VERSION}"
        if [ "${tag}" = "GE-Proton" ]; then
            tag="$(resolve_latest_ge_proton)" || tag=""
            [ -n "${tag}" ] || { gow_log "ERROR: could not resolve the latest GE-Proton release"; exit 1; }
        fi
        install_ge_proton "${tag}" || exit 1
        PROTON_VERSION="${PROTON_DIR}/${tag}"
        ;;
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
