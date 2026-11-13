"""Prepares the RetrOS/LT build tree from the pinned MS-DOS 2.x source.

    python3 scripts/prep.py WORKDIR

Copies upstream/msdos/v2.0/source to WORKDIR/SRC with the line endings and
end-of-file marks the 1982 tools expect, applies RetrOS/LT's patches
(patches/series), and adds RetrOS/LT's own files (src/).
"""
import shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / "upstream" / "msdos" / "v2.0" / "source"
TEXT = {".ASM", ".TXT", ""}


def clean(b):
    """LF lines, nothing after the first ^Z, no NUL padding."""
    i = b.find(b"\x1a")
    if i >= 0:
        b = b[:i]
    b = b.replace(b"\x00", b"")
    # A few files were edited in WordStar, which marks a line it reflowed
    # with the high bit of its line feed: CR 8Ah.
    b = b.replace(b"\r\x8a", b"\n").replace(b"\r\n", b"\n")
    return b


def main():
    work = Path(sys.argv[1]).resolve()
    src = work / "SRC"
    if src.exists():
        shutil.rmtree(src)
    src.mkdir(parents=True)
    # 1. the published files, LF line endings for patching, upper-case names
    for f in sorted(UP.iterdir()):
        b = f.read_bytes()
        if f.suffix.upper() in TEXT:
            b = clean(b)
        (src / f.name.upper()).write_bytes(b)
    # 2. the patches
    series = ROOT / "patches" / "series"
    for line in series.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        with open(ROOT / "patches" / line, "rb") as p:
            r = subprocess.run(["patch", "-d", str(src), "-p1", "--binary", "-s",
                                "--no-backup-if-mismatch"], stdin=p)
        if r.returncode:
            sys.exit(f"prep.py: {line} does not apply")
    # 3. RetrOS/LT's own files
    for f in sorted((ROOT / "src").iterdir()):
        if f.is_file():
            (src / f.name.upper()).write_bytes(clean(f.read_bytes()))
    # 4. CR LF and a ^Z for the 1982-era tools
    for f in src.iterdir():
        if f.suffix.upper() in TEXT:
            b = f.read_bytes().replace(b"\n", b"\r\n") + b"\x1a"
            f.write_bytes(b)
    print(f"prepared {src}")


if __name__ == "__main__":
    main()
