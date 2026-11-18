# SPDX-License-Identifier: MIT
# Build environment for the Pixel 2 (walleye) Ubuntu port.
# Runs natively as arm64 on Apple Silicon: no QEMU, no cross-compiler for the
# main kernel. The stock kernel was built with Android clang 11.0.1, so we
# use Ubuntu's clang-11 to match.
# On an x86 host build-kernel.sh uses an amd64 build of this image instead
# (scripts/dev.sh, DEV_CROSS=1), which adds the aarch64 binutils/gcc.
FROM ubuntu:20.04
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev \
        clang-11 lld-11 llvm-11 ccache \
        gcc-arm-linux-gnueabi \
        lz4 cpio kmod git ca-certificates curl wget xz-utils file \
        python2 python3 \
        android-sdk-libsparse-utils e2fsprogs \
        busybox-static device-tree-compiler \
    && if [ "$TARGETARCH" = amd64 ]; then \
        apt-get install -y --no-install-recommends binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# Unversioned clang/ld.lld names, as the kernel Makefile expects.
RUN for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip; do \
        ln -sf /usr/bin/$t-11 /usr/local/bin/$t; \
    done \
    && ln -sf /usr/bin/python2 /usr/local/bin/python

# Third-party sources (kernel, mkbootimg) are git submodules in external/,
# mounted at /work/external at run time. See scripts/dev.sh.
ENV PATH="/work/scripts/bin:${PATH}"

WORKDIR /work
