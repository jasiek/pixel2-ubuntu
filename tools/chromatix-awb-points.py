#!/usr/bin/env python3
"""Print the AWB reference points of a Qualcomm chromatix 3A library (P8.5).

    tools/chromatix-awb-points.py libchromatix_<sensor>_pixel_res0_snapshot_3a.so

The wahoo 3A libs keep 16 (R/G, B/G) float pairs at .data 0x30..0xb0, the
raw sensor ratios of the vendor's white references. For a libcamera Bayes
AWB 'colourGains' curve the gains are their reciprocals, and each point's ct
is what libipa estimateCCT() returns for it, so a grey scene maps onto
itself. Merge points under 100 K apart by hand (average both).
Checked: on walleye's imx362 lib this reproduces Porthole's rear curve.
Run with python3 -I on the copied library (it is untrusted input).
"""
import sys, struct
def data_section(f):
    d = open(f, 'rb').read()
    assert d[:4] == b'\x7fELF' and d[4] == 1, 'expect ELF32'
    shoff, = struct.unpack_from('<I', d, 0x20); shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x2e)
    secs = [struct.unpack_from('<IIIIIIIIII', d, shoff + i * shentsize) for i in range(shnum)]
    strtab = secs[shstrndx][4]
    for s in secs:
        name = d[strtab + s[0]: d.index(b'\0', strtab + s[0])].decode()
        if name == '.data':
            return d[s[4]: s[4] + s[5]]
def cct(r, g, b):
    m = [[-0.14282, 1.54924, -0.95641], [-0.32466, 1.57837, -0.73191], [-0.68202, 0.77073, 0.56332]]
    x, y, z = (m[i][0] * r + m[i][1] * g + m[i][2] * b for i in range(3)); t = x + y + z; x, y = x / t, y / t
    n = (x - 0.3320) / (0.1858 - y)
    return int(449 * n**3 + 3525 * n**2 + 6823.3 * n + 5520.33)
d = data_section(sys.argv[1])
fl = struct.unpack_from('<32f', d, 0x30)
pts = sorted({(cct(rg, 1.0, bg), round(1 / rg, 4), round(1 / bg, 4), round(rg, 4), round(bg, 4)) for rg, bg in zip(fl[0::2], fl[1::2])})
for p in pts: print('ct %5d gains [ %.4f, %.4f ]  raw R/G %.4f B/G %.4f' % p)
