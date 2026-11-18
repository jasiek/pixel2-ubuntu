#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build tools/pixel2-screen.c (static arm64) -> build/screen/pixel2-screen.
# The font is cut from the kernel submodule (lib/fonts/font_8x16.c, the VGA
# font in CP437 order, matching the VT's glyph codes), so no font file is
# committed. Runs inside the build container (re-execs via scripts/dev.sh).
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-screen.sh "$@"
fi
OUT=/work/build/screen
mkdir -p "$OUT"
sed -n '/^static const unsigned char fontdata_8x16/,/^};/p' \
    /work/external/kernel-msm/lib/fonts/font_8x16.c \
    | sed 's/FONTDATAMAX/4096/' > "$OUT/font_8x16.h"
gcc -O2 -Wall -Wextra -static -I"$OUT" -o "$OUT/pixel2-screen" /work/tools/pixel2-screen.c
ls -la "$OUT/pixel2-screen"
