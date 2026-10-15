"""Reads Jagged Alliance 2 .STI (STCI) images and writes PNGs. Local placeholder tooling only.

Supports the 8-bit indexed ETRLE format (items, faces, tiles, soldier animations). Usage:
    python tools/ja2_sti.py read FILE.STI            # print header and sub-image sizes
    python tools/ja2_sti.py png FILE.STI OUT.png     # first sub-image as a PNG (transparent background)
    python tools/ja2_sti.py sheet FILE.STI OUT.png   # every sub-image in a grid
The STI files themselves are third-party (see docs/LICENSE_AUDIT.md) and are never committed.
"""
import struct
import sys

from PIL import Image

FLAG_RGB, FLAG_INDEXED, FLAG_ZLIB, FLAG_ETRLE = 0x04, 0x08, 0x10, 0x20


class Sti:
    def __init__(self, path):
        data = open(path, "rb").read()
        if data[:4] != b"STCI":
            raise ValueError("not an STCI file: %s" % path)
        self.original, self.stored, self.transparent, self.flags, self.height, self.width = struct.unpack_from("<IIIIHH", data, 4)
        if not self.flags & FLAG_INDEXED:
            raise ValueError("only indexed STI is supported (%s)" % path)
        colours, subs = struct.unpack_from("<IH", data, 24)
        self.palette = [tuple(data[64 + i * 3: 67 + i * 3]) for i in range(colours)]
        pos = 64 + colours * 3
        self.frames = []
        heads = []
        for i in range(subs):
            heads.append(struct.unpack_from("<IIhhHH", data, pos + i * 16))
        base = pos + subs * 16
        for off, length, ox, oy, h, w in heads:
            self.frames.append({"ox": ox, "oy": oy, "w": w, "h": h, "data": data[base + off: base + off + length]})
        if subs == 0:  # a single, plain image
            self.frames.append({"ox": 0, "oy": 0, "w": self.width, "h": self.height, "data": data[pos:]})

    def image(self, index=0):
        f = self.frames[index]
        w, h, src = f["w"], f["h"], f["data"]
        img = Image.new("RGBA", (max(w, 1), max(h, 1)), (0, 0, 0, 0))
        px = img.load()
        x = y = i = 0
        if not self.flags & FLAG_ETRLE:
            for k, c in enumerate(src[: w * h]):
                if c:
                    r, g, b = self.palette[c]
                    px[k % w, k // w] = (r, g, b, 255)
            return img
        while i < len(src) and y < h:
            b = src[i]
            i += 1
            if b == 0:
                x, y = 0, y + 1
            elif b & 0x80:
                x += b & 0x7F
            else:
                for c in src[i: i + b]:
                    if x < w:
                        r, g, bl = self.palette[c]
                        px[x, y] = (r, g, bl, 255)
                    x += 1
                i += b
        return img


def sheet(sti, columns=8):
    imgs = [sti.image(i) for i in range(len(sti.frames))]
    cw = max(i.width for i in imgs)
    ch = max(i.height for i in imgs)
    rows = (len(imgs) + columns - 1) // columns
    out = Image.new("RGBA", (cw * min(columns, len(imgs)), ch * rows), (40, 40, 48, 255))
    for n, im in enumerate(imgs):
        out.alpha_composite(im, ((n % columns) * cw, (n // columns) * ch))
    return out


if __name__ == "__main__":
    cmd, path = sys.argv[1], sys.argv[2]
    sti = Sti(path)
    if cmd == "read":
        print("%dx%d flags=%#x colours=%d frames=%d" % (sti.width, sti.height, sti.flags, len(sti.palette), len(sti.frames)))
        for f in sti.frames[:12]:
            print("  %dx%d offset (%d,%d)" % (f["w"], f["h"], f["ox"], f["oy"]))
    elif cmd == "png":
        sti.image(0).save(sys.argv[3])
    elif cmd == "sheet":
        sheet(sti).save(sys.argv[3])
