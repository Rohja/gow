ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:fedora

######################################
# Same as Steam/Lutris: a patched bubblewrap that works with
# CAP_SYS_ADMIN in containers (needed by umu's pressure-vessel runtime).
# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE} AS bwrap-builder

WORKDIR /root
COPY ignore_capabilities.patch /root/
RUN dnf install -y git meson ca-certificates dpkg-dev && \
    git clone https://github.com/containers/bubblewrap && \
    cd bubblewrap && \
    ./ci/builddeps.sh && \
    patch -p1 < ../ignore_capabilities.patch && \
    meson _builddir && \
    meson compile -C _builddir

######################################

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

# "latest" is resolved at build time (the CI passes the resolved tag so the layer cache
# is invalidated on new releases). Proton builds can require a newer umu runtime table.
ARG UMU_VERSION=latest

# umu-launcher is not available in the Fedora repos: use the upstream zipapp release
RUN <<_INSTALL_UMU
set -e
dnf install -y \
    python3 \
    python3-xlib \
    python3-filelock \
    mesa-vulkan-drivers.i686 \
    mesa-dri-drivers.i686 \
    vulkan-loader.i686 \
    zenity \
    cabextract \
    curl \
    tar \
    xz \
    zstd
dnf clean all

if [ "${UMU_VERSION}" = "latest" ]; then
    UMU_VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://github.com/Open-Wine-Components/umu-launcher/releases/latest | sed 's#.*/##')"
fi
[ -n "${UMU_VERSION}" ] && [ "${UMU_VERSION}" != "latest" ] || { echo "cannot resolve umu-launcher version" >&2; exit 1; }
echo "Installing umu-launcher ${UMU_VERSION}"
mkdir -p /opt/umu /tmp/umu
curl -fsSL -o /tmp/umu/umu.tar \
    "https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_VERSION}/umu-launcher-${UMU_VERSION}-zipapp.tar"
tar -xf /tmp/umu/umu.tar -C /opt/umu
UMU_RUN="$(find /opt/umu -name umu-run -type f | head -n1)"
chmod +x "${UMU_RUN}"
ln -s "${UMU_RUN}" /usr/local/bin/umu-run
rm -rf /tmp/umu
_INSTALL_UMU

COPY --from=bwrap-builder --chmod=755 /root/bubblewrap/_builddir/bwrap /usr/bin/bwrap

RUN mkdir -pm 777 /var/umu /game

COPY --chmod=777 scripts/startup.sh /opt/gow/startup-app.sh

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
