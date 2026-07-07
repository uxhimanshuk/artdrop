#!/usr/bin/env python3
import struct
import zlib
from pathlib import Path


def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def png(path, size, rgba):
    r, g, b, a = rgba
    raw = b"".join(bytes([0]) + bytes([r, g, b, a]) * size for _ in range(size))
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9))
    data += chunk(b"IEND", b"")
    path.write_bytes(data)


def main():
    out = Path(__file__).resolve().parents[1] / "icons"
    out.mkdir(exist_ok=True)
    charcoal = (24, 24, 22, 255)
    png(out / "icon-192.png", 192, charcoal)
    png(out / "icon-512.png", 512, charcoal)


if __name__ == "__main__":
    main()
