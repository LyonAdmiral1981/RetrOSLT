"""Makes a RetrOS/LT fixed disk image: one DOS partition over the whole disk,
formatted as DOS 2 formats a fixed disk, with the system on it.

    python3 scripts/mkhd.py OUT.IMG [CYLS HEADS SPT] [FILE...]

The default geometry is the IBM PC XT's 10 MB disk: 306 cylinders, 4 heads,
17 sectors a track. (A test image until FDISK and FORMAT exist.)
"""
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "OUTPUT"


def run(*a):
    subprocess.run(a, check=True)


def main():
    args = sys.argv[1:]
    img = Path(args.pop(0))
    cyl, hds, spt = 306, 4, 17
    if len(args) >= 3 and all(a.isdigit() for a in args[:3]):
        cyl, hds, spt = (int(a) for a in args[:3]); args = args[3:]
    total = cyl * hds * spt
    start = spt                               # cylinder 0, head 1
    secs = total - start
    if secs > 65535:
        sys.exit("a DOS 2 volume is at most 65535 sectors")
    spc, root = 8, 512
    while True:                               # 12-bit FAT: at most 4084 clusters
        fat = 1
        while True:
            data = secs - 1 - 2 * fat - root // 16
            clus = data // spc
            if (clus + 2) * 3 // 2 <= fat * 512:
                break
            fat += 1
        if clus <= 4084:
            break
        spc *= 2
    for asm, binf in (("MBR.ASM", "MBR.BIN"), ("BOOT.ASM", "BOOT.BIN")):
        run("nasm", "-f", "bin", "-o", str(ROOT / "build" / binf), str(ROOT / "boot" / asm))
    mbr = bytearray((ROOT / "build" / "MBR.BIN").read_bytes())
    end_c, end_h, end_s = cyl - 1, hds - 1, spt
    e = bytes([0x80, 1, 1, 0, 0x01, end_h, ((end_c >> 2) & 0xC0) | end_s, end_c & 0xFF]) + \
        start.to_bytes(4, "little") + secs.to_bytes(4, "little")
    mbr[0x1BE:0x1CE] = e
    boot = bytearray((ROOT / "build" / "BOOT.BIN").read_bytes())
    boot[11:30] = (512).to_bytes(2, "little") + bytes([spc]) + (1).to_bytes(2, "little") + bytes([2]) + \
        root.to_bytes(2, "little") + secs.to_bytes(2, "little") + bytes([0xF8]) + fat.to_bytes(2, "little") + \
        spt.to_bytes(2, "little") + hds.to_bytes(2, "little") + start.to_bytes(2, "little")
    d = bytearray(total * 512)
    d[0:512] = mbr
    o = start * 512
    d[o:o + 512] = boot
    for f in range(2):
        p = o + (1 + f * fat) * 512
        d[p:p + 3] = b"\xF8\xFF\xFF"
    img.write_bytes(d)
    part = f"{img}@@{o}"
    for f in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM"):
        run("mcopy", "-i", part, str(OUT / f), "::" + f)
    run("mattrib", "-i", part, "+h", "+s", "+r", "::IO.SYS", "::MSDOS.SYS")
    for f in args:
        run("mcopy", "-i", part, f, "::")
    print(f"{img}: {cyl}x{hds}x{spt}, {secs} sectors, {spc} a cluster, {clus} clusters, FAT {fat}")


if __name__ == "__main__":
    main()
