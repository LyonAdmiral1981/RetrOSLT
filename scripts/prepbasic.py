#!/usr/bin/env python3
"""prepbasic.py WORKDIR NAME: Microsoft's GW-BASIC source, ready to build.

Copies the pinned upstream/gwbasic files into WORKDIR, cleaned as prep.py
cleans the MS-DOS source (cut at ^Z, no NULs, LF), joins MATH1.ASM and
MATH2.ASM (one module split in two files), applies patches/gwbasic in the
order of their series file, adds RetrOS's IBM PC layer (basic/PCIO.ASM)
and PCIOID.INC naming the edition (NAME, e.g. "RetrOS/LT BASIC Version
1.0"), and writes everything with CR LF, as MASM expects.
"""
import pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UP = ROOT / "upstream" / "gwbasic"
HEADERS = ["BINTRP.H", "IBMRES.H", "OEM.H", "GIO86U", "MSDOSU"]

def clean(b):
    b = b.split(b"\x1a")[0].replace(b"\0", b"")
    return b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

def main():
    work, name = pathlib.Path(sys.argv[1]), sys.argv[2]
    work.mkdir(parents=True, exist_ok=True)
    for f in sorted(UP.glob("*.ASM")) + [UP / h for h in HEADERS]:
        if f.name in ("MATH1.ASM", "MATH2.ASM"):
            continue
        (work / f.name).write_bytes(clean(f.read_bytes()))
    (work / "MATH.ASM").write_bytes(clean((UP / "MATH1.ASM").read_bytes()) +
                                    clean((UP / "MATH2.ASM").read_bytes()))
    series = ROOT / "patches" / "gwbasic" / "series"
    for line in series.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            subprocess.run(["patch", "-s", "-p1", "-d", str(work), "-i",
                            str(series.parent / line)], check=True)
    (work / "PCIO.ASM").write_bytes(clean((ROOT / "basic" / "PCIO.ASM").read_bytes()))
    (work / "PCIOID.INC").write_bytes(f'BASNAM\tEQU\t<"{name}">\n'.encode())
    for f in work.iterdir():
        if f.suffix in (".ASM", ".H", ".INC") or f.name in HEADERS:
            f.write_bytes(f.read_bytes().replace(b"\n", b"\r\n"))

if __name__ == "__main__":
    main()
