"""Makes the RetrOS/LT distribution diskettes from build/OUTPUT, as PC DOS
2.10 came: two single-sided 180 KB diskettes, which any IBM PC or PC XT
drive reads.

    python3 scripts/mkinstall.py [OUTDIR]          (default build/install)

RETROS-LT-DOS.IMG
    The DOS diskette. It starts the computer, and holds the system, the
    commands and Install. Its AUTOEXEC.BAT asks the date and time and runs
    Install, which can be left with Esc.
RETROS-LT-SUPPLEMENTAL.IMG
    The Supplemental Programs diskette: DEBUG, LINK, EXE2BIN, and BASIC
    (BASICA.EXE, Microsoft's GW-BASIC, and BASIC.COM) with RetrOS's sample
    programs.

Each holds a hidden RETROS.DSK ("RetrOS/LT 1" or "RetrOS/LT 2") for
Install to check. Every file carries the release date and time, as IBM's
diskettes did. FC, which PC DOS 2.10 does not have, comes on the DOS
diskette as an extra.
"""
import os, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "OUTPUT"
DIST = ROOT / "dist"
RELEASE = "2026-11-13 12:00"                 # date and time on every file

DOS = ["RETBIO.COM", "RETDOS.COM", "COMMAND.COM", "ANSI.SYS", "FORMAT.COM",
       "CHKDSK.COM", "SYS.COM", "DISKCOPY.COM", "DISKCOMP.COM", "COMP.COM",
       "FC.EXE", "EDLIN.COM", "MODE.COM", "FDISK.COM", "BACKUP.COM", "RESTORE.COM",
       "PRINT.COM", "RECOVER.COM", "ASSIGN.COM", "TREE.COM", "GRAPHICS.COM",
       "SORT.EXE", "FIND.EXE", "MORE.COM", "INSTALL.COM"]
SUPPLEMENTAL = ["EXE2BIN.EXE", "LINK.EXE", "DEBUG.COM", "BASIC.COM", "BASICA.EXE"]
SAMPLES = ["CLOCK.BAS", "TUNES.BAS", "PALETTE.BAS", "SKETCH.BAS", "LOAN.BAS", "BOUNCE.BAS"]


def run(*a):
    subprocess.run(a, check=True, env={**os.environ, "MTOOLS_SKIP_CHECK": "1",
                                       "MTOOLS_NO_VFAT": "1"})


def blank(img):
    """A 180 KB diskette as FORMAT leaves it: the RetrOS/LT boot sector with
    a single-sided, 9-sector BPB (media FC), empty FATs and directory."""
    tot, spc, root, media, fat, spt, hds = 360, 1, 64, 0xFC, 2, 9, 1
    b = bytearray((ROOT / "build" / "BOOT.BIN").read_bytes())
    b[11:30] = (512).to_bytes(2, "little") + bytes([spc]) + (1).to_bytes(2, "little") + \
        bytes([2]) + root.to_bytes(2, "little") + tot.to_bytes(2, "little") + bytes([media]) + \
        fat.to_bytes(2, "little") + spt.to_bytes(2, "little") + hds.to_bytes(2, "little") + bytes(2)
    data = bytearray(tot * 512)
    data[0:512] = b
    for f in range(2):
        o = (1 + f * fat) * 512
        data[o:o + 3] = bytes([media, 0xFF, 0xFF])
    img.write_bytes(data)


def put(img, stage, files, hidden=()):
    stamp = time.mktime(time.strptime(RELEASE, "%Y-%m-%d %H:%M"))
    for f in files:
        os.utime(stage / f, (stamp, stamp))
        run("mcopy", "-m", "-i", str(img), str(stage / f), "::" + f)
    if hidden:
        run("mattrib", "-i", str(img), "+h", "+s", "+r", *("::" + f for f in hidden))


def main():
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "install"
    dest.mkdir(parents=True, exist_ok=True)
    run("nasm", "-f", "bin", "-o", str(ROOT / "build" / "BOOT.BIN"), str(ROOT / "boot" / "BOOT.ASM"))
    stage = ROOT / "build" / "stage"
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir()
    for f in DOS + SUPPLEMENTAL:
        shutil.copy(OUT / f, stage / f)
    for f in SAMPLES:                        # BASIC programs: CR LF, ^Z
        (stage / f).write_bytes((ROOT / "basic" / "samples" / f).read_bytes()
                                .replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") + b"\x1a")
    for f in ("LICENSE.TXT", "NOTICE.TXT"):
        (stage / f).write_bytes((DIST / f).read_bytes().replace(b"\r\n", b"\n")
                                .replace(b"\n", b"\r\n") + b"\x1a")
    (stage / "AUTOEXEC.BAT").write_bytes(b"DATE\r\nTIME\r\nINSTALL\r\n")

    dos = dest / "RETROS-LT-DOS.IMG"
    blank(dos)
    (stage / "RETROS.DSK").write_bytes(b"RetrOS/LT 1\r\n")
    put(dos, stage, ["RETBIO.COM", "RETDOS.COM"], hidden=["RETBIO.COM", "RETDOS.COM"])
    put(dos, stage, DOS[2:] + ["LICENSE.TXT", "NOTICE.TXT", "AUTOEXEC.BAT"])
    put(dos, stage, ["RETROS.DSK"], hidden=["RETROS.DSK"])

    sup = dest / "RETROS-LT-SUPPLEMENTAL.IMG"
    blank(sup)
    (stage / "RETROS.DSK").write_bytes(b"RetrOS/LT 2\r\n")
    put(sup, stage, SUPPLEMENTAL + SAMPLES)
    put(sup, stage, ["RETROS.DSK"], hidden=["RETROS.DSK"])

    for img in (dos, sup):
        free = subprocess.run(["mdir", "-i", str(img), "::"], capture_output=True, text=True,
                              env={**os.environ, "MTOOLS_SKIP_CHECK": "1"}).stdout.strip().splitlines()[-1]
        print(f"{img.name}: {free.strip()}")


if __name__ == "__main__":
    main()
