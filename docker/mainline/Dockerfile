# Build environment for the mainline kernel experiment (P8.3).
# Kernel 7.x needs a newer toolchain than the 20.04 container used for the
# downstream 4.4 kernel (docker/Dockerfile), so it gets its own image.
# Native arm64 on Apple Silicon.
FROM --platform=linux/arm64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev \
        lz4 gzip cpio kmod git ca-certificates file \
        python3 device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
