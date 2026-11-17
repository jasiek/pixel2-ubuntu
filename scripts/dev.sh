#!/usr/bin/env bash
# Run a command inside the arm64 build container with the repo at /work.
#   scripts/dev.sh uname -m
#   scripts/dev.sh            # interactive shell
# Builds the image on first use. Pass --privileged only to scripts that need
# loop devices (rootfs packing); see build-rootfs.sh.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"   # physical path on /Volumes/Pixel2Dev
IMAGE="${DEV_IMAGE:-pixel2-build}"          # DEV_IMAGE=pixel2-mainline-build for P8.3
DOCKERDIR="${DEV_DOCKERDIR:-docker}"        # with DEV_DOCKERDIR=docker/mainline

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build --platform linux/arm64 -t "$IMAGE" "$REPO/$DOCKERDIR"
fi

tty_flags=()
[ -t 0 ] && [ -t 1 ] && tty_flags=(-it)

[ $# -eq 0 ] && set -- bash

exec docker run --rm "${tty_flags[@]}" \
    ${DEV_DOCKER_ARGS:-} \
    -v "$REPO:/work" -w /work \
    "$IMAGE" "$@"
