ARG BASE_APP_IMAGE

######################################
# Same as Steam/Lutris: a patched bubblewrap that works with
# CAP_SYS_ADMIN in containers (needed by umu's pressure-vessel runtime).
# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE} AS bwrap-builder

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /root
COPY ignore_capabilities.patch /root/
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends git meson ca-certificates dpkg-dev && \
    git clone https://github.com/containers/bubblewrap && \
    cd bubblewrap && \
    ./ci/builddeps.sh && \
    patch -p1 < ../ignore_capabilities.patch && \
    meson _builddir && \
    meson compile -C _builddir

######################################

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
# "latest" is resolved at build time (the CI passes the resolved tag so the layer cache
# is invalidated on new releases). Proton builds can require a newer umu runtime table.
ARG UMU_VERSION=latest

ARG REQUIRED_PACKAGES=" \
    python3 \
    python3-xlib \
    python3-filelock \
    libc6:i386 \
    libgl1:i386 \
    libegl1:i386 \
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386 \
    libsdl2-2.0-0:i386 \
    libfreetype6:i386 \
    libasound2-plugins:i386 \
    cabextract \
    curl \
    zenity \
    xz-utils \
    zstd \
    "

# hadolint ignore=DL3008
RUN <<_INSTALL_UMU
set -e
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends ${REQUIRED_PACKAGES}

# umu-launcher: use the upstream zipapp release (single `umu-run` executable)
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

rm -rf /tmp/umu /var/lib/apt/lists/*
_INSTALL_UMU

COPY --from=bwrap-builder --chmod=755 /root/bubblewrap/_builddir/bwrap /usr/bin/bwrap

# Persistent volume (Proton, Steam Linux Runtime, wine prefix) and app folder
RUN mkdir -pm 777 /var/umu /app

COPY --chmod=777 scripts/startup.sh /opt/gow/startup-app.sh

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
