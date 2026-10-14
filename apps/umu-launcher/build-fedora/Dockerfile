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

RUN <<_INSTALL_UMU
set -e
dnf install -y \
    umu-launcher \
    mesa-vulkan-drivers.i686 \
    mesa-dri-drivers.i686 \
    vulkan-loader.i686 \
    zenity \
    cabextract \
    curl \
    xz \
    zstd
dnf clean all
_INSTALL_UMU

COPY --from=bwrap-builder --chmod=755 /root/bubblewrap/_builddir/bwrap /usr/bin/bwrap

RUN mkdir -pm 777 /var/umu /app

COPY --chmod=777 scripts/startup.sh /opt/gow/startup-app.sh

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
