#!/usr/bin/env python3
"""Extract a 256-point transfer curve from an exported ramp image.

The source chart is a 1024x256 horizontal ramp, 4px per level (level =
x//4). For each level we average the green channel over the level's 4
columns x all rows of the EXPORTED image (same geometry — SEP exports
1:1). Output: CSV 'level,out' with out in 0..255 float.

Input handling: convert anything to BMP via sips first (uncompressed,
trivially parseable, no deps).
"""
import subprocess, struct, sys, os, tempfile

def load_bmp_pixels(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:2] == b"BM", "not a BMP"
    pixel_off = struct.unpack("<I", data[10:14])[0]
    hdr_size = struct.unpack("<I", data[14:18])[0]
    width = struct.unpack("<i", data[18:22])[0]
    height = struct.unpack("<i", data[22:26])[0]
    bpp = struct.unpack("<H", data[28:30])[0]
    assert bpp in (24, 32), f"unsupported bpp {bpp}"
    nb = bpp // 8
    row_size = (width * nb + 3) & ~3
    flipped = height > 0
    height = abs(height)
    def px(x, y):
        yy = (height - 1 - y) if flipped else y
        off = pixel_off + yy * row_size + x * nb
        b, g, r = data[off], data[off + 1], data[off + 2]
        return r, g, b
    return width, height, px

def main():
    src = sys.argv[1]
    out_csv = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".csv"
    with tempfile.NamedTemporaryFile(suffix=".bmp", delete=False) as t:
        bmp = t.name
    subprocess.run(["sips", "-s", "format", "bmp", src, "--out", bmp],
                   check=True, capture_output=True)
    width, height, px = load_bmp_pixels(bmp)
    os.unlink(bmp)
    assert width == 1024, f"unexpected width {width}"
    rows = range(0, height, max(1, height // 64))  # sample rows for speed
    lines = ["level,out"]
    for level in range(256):
        total = 0.0
        n = 0
        for x in range(level * 4, level * 4 + 4):
            for y in rows:
                total += px(x, y)[1]
                n += 1
        lines.append(f"{level},{total / n:.3f}")
    open(out_csv, "w").write("\n".join(lines) + "\n")
    print(out_csv)

if __name__ == "__main__":
    main()
