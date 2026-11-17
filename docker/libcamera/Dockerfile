# Builds libcamera (external/libcamera + Porthole's patches) for the phone's
# Ubuntu 24.04 arm64 (P8.5). Same base as the rootfs, so the binaries link
# against the phone's own libraries.
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential meson ninja-build pkg-config patch ca-certificates \
        python3-yaml python3-ply python3-jinja2 \
        libyaml-dev libudev-dev libevent-dev libgnutls28-dev openssl \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        libtiff-dev libjpeg-dev libyuv-dev libdrm-dev libdw-dev libunwind-dev \
    && rm -rf /var/lib/apt/lists/*
