"""Makes a RetrOS/LT startup diskette image from build/OUTPUT.

    python3 scripts/mkboot.py OUT.IMG [SIZE] [FILE...]

SIZE is 360 (the default), 320, 180 or 160. IO.SYS and MSDOS.SYS are put
first, as DOS 2 requires, then COMMAND.COM and any FILEs.
"""
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "OUTPUT"
# size: (total sectors, sectors per cluster, root entries, media, FAT sectors, spt, heads)
FORMATS = {360: (720, 2, 112, 0xFD, 2, 9, 2), 320: (640, 2, 112, 0xFF, 1, 8, 2),
           180: (360, 1, 64, 0xFC, 2, 9, 1), 160: (320, 1, 64, 0xFE, 1, 8, 1)}


def run(*a):
    subprocess.run(a, check=True)


def main():
    img = Path(sys.argv[1])
    size = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 360
    extra = [a for a in sys.argv[2:] if not a.isdigit()]
    tot, spc, root, media, fat, spt, hds = FORMATS[size]
    boot = ROOT / "build" / "BOOT.BIN"
    run("nasm", "-f", "bin", "-o", str(boot), str(ROOT / "boot" / "BOOT.ASM"))
    b = bytearray(boot.read_bytes())
    b[11:30] = (512).to_bytes(2, "little") + bytes([spc]) + (1).to_bytes(2, "little") + \
        bytes([2]) + root.to_bytes(2, "little") + tot.to_bytes(2, "little") + bytes([media]) + \
        fat.to_bytes(2, "little") + spt.to_bytes(2, "little") + hds.to_bytes(2, "little") + bytes(2)
    data = bytearray(tot * 512)
    data[0:512] = b
    for f in range(2):                       # both FATs: media byte, FF, FF
        o = (1 + f * fat) * 512
        data[o:o + 3] = bytes([media, 0xFF, 0xFF])
    img.write_bytes(data)
    run("mcopy", "-i", str(img), str(OUT / "IO.SYS"), "::IO.SYS")
    run("mcopy", "-i", str(img), str(OUT / "MSDOS.SYS"), "::MSDOS.SYS")
    run("mcopy", "-i", str(img), str(OUT / "COMMAND.COM"), "::COMMAND.COM")
    run("mattrib", "-i", str(img), "+h", "+s", "+r", "::IO.SYS", "::MSDOS.SYS")
    for e in extra:
        run("mcopy", "-i", str(img), e, "::")
    print(f"{img}: {size} KB")


if __name__ == "__main__":
    main()
