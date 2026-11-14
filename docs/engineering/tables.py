"""Writes the two tables of the RetrOS/LT Guide to Engineering that would
go stale if typed in: Appendix A's source files with their line counts
(files.gen.tex), and Appendix B's patches, each with the files it changes
and the lines it adds and removes in each (patches.gen.tex).

    python3 tables.py            (run by build.sh)
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

# Appendix A: every file of RetrOS/LT's own, and what it is. A file listed
# here that is missing stops the build; so does one of these directories
# holding a file not listed, so the table cannot fall behind.
FILES = [
    ("src/BIOS.ASM", "RETBIO.COM (Section~3)"),
    ("src/IO.ASM", "The kernel's console functions, reconstructed (Section~4)"),
    ("src/IBMFOR.ASM", "FORMAT's part for the IBM PC (Section~5)"),
    ("boot/BOOT.ASM", "The startup record (Section~3)"),
    ("boot/MBR.ASM", "The master boot record (Section~3)"),
    ("cmd/ASSIGN.ASM", "ASSIGN (Section~5)"),
    ("cmd/BACKUP.ASM", "BACKUP (Section~5)"),
    ("cmd/RESTORE.ASM", "RESTORE (Section~5)"),
    ("cmd/BR.INC", "What BACKUP and RESTORE share"),
    ("cmd/COMP.ASM", "COMP (Section~5)"),
    ("cmd/DISKCOMP.ASM", "DISKCOMP (Section~5)"),
    ("cmd/DISKCOPY.ASM", "DISKCOPY (Section~5)"),
    ("cmd/FLOPPY.INC", "What DISKCOPY and DISKCOMP share"),
    ("cmd/FDISK.ASM", "FDISK (Section~5)"),
    ("cmd/GRAPHICS.ASM", "GRAPHICS (Section~5)"),
    ("cmd/MODE.ASM", "MODE (Section~5)"),
    ("cmd/TREE.ASM", "TREE (Section~5)"),
    ("dev/ANSI.ASM", "ANSI.SYS (Section~5)"),
    ("install/INSTALL.ASM", "Install (Section~6)"),
    ("basic/PCIO.ASM", "BASIC's part for the IBM PC (Section~8)"),
    ("basic/BASIC.ASM", "BASIC.COM (Section~8)"),
    ("basic/samples/BOUNCE.BAS", "Sample program"),
    ("basic/samples/CLOCK.BAS", "Sample program"),
    ("basic/samples/LOAN.BAS", "Sample program"),
    ("basic/samples/PALETTE.BAS", "Sample program"),
    ("basic/samples/SKETCH.BAS", "Sample program"),
    ("basic/samples/TUNES.BAS", "Sample program"),
    ("patches/gwbasic/series", "GW-BASIC's series (Appendix~B)"),
    ("scripts/prepbasic.py", "Makes BASIC's build tree (Section~8)"),
    ("scripts/buildbasic.sh", "Builds BASIC (Section~8)"),
    ("patches/series", "The series (Appendix~B)"),
    ("scripts/prep.py", "Makes the build tree (Section~2)"),
    ("scripts/build.sh", "Builds everything (Section~2)"),
    ("scripts/dosrun.sh", "Runs the 1988 tools in DOSBox-X (Section~2)"),
    ("scripts/mkboot.py", "A startup diskette image, for tests"),
    ("scripts/mkhd.py", "A fixed disk image, for tests"),
    ("scripts/mkinstall.py", "The two distribution diskettes (Section~6)"),
    ("dist/LICENSE.TXT", "The RetrOS/LT License"),
    ("dist/NOTICE.TXT", "Microsoft's notice"),
    ("tests/qpc.py", "A PC under QEMU (Section~7)"),
    ("tests/hd_test.py", "FDISK, FORMAT and starting from the fixed disk (Section~7)"),
    ("tests/install_test.py", "Install onto an empty fixed disk (Section~7)"),
    ("tests/basic_test.py", "BASIC from the diskettes (Section~7)"),
    ("tests/mame5150/setup.sh", "Prepares MAME's IBM PC 5150 (Section~7)"),
    ("tests/mame5150/screen.lua", "Saves the screen from video memory"),
    ("tests/mame5150/swap.lua", "Changes the diskette in drive A"),
    ("tests/mame5150/WAITSWAP.ASM", "Asks for the diskette change"),
]
CHECKED = ["src", "boot", "cmd", "dev", "install", "scripts", "tests", "tests/mame5150", "dist",
           "basic", "basic/samples"]
IGNORE = re.compile(r"(README\.md|\.gitignore|\.COM|\.pyc)$")


def tex(s):
    return s.replace("_", "\\_")


def files_table():
    rows, named = [], set()
    for path, what in FILES:
        f = ROOT / path
        if not f.exists():
            sys.exit(f"tables.py: {path} is in Appendix A's list but missing")
        named.add(path)
        n = len(f.read_bytes().splitlines())
        rows.append(f"\\file{{{tex(path)}}} & {n:,} & {what}\\\\")
    for d in CHECKED:
        for f in sorted((ROOT / d).iterdir()):
            rel = f"{d}/{f.name}"
            if f.is_file() and not IGNORE.search(f.name) and rel not in named:
                sys.exit(f"tables.py: {rel} is not in Appendix A's list")
    (HERE / "files.gen.tex").write_text("\n".join(rows) + "\n")


def patches_table():
    rows = []
    for d, mark in (("patches", ""), ("patches/gwbasic", "GW ")):
        rows += series_rows(ROOT / d, mark)
    (HERE / "patches.gen.tex").write_text("\n".join(rows) + "\n")


def series_rows(d, mark):
    rows = []
    series = [l.strip() for l in (d / "series").read_text().splitlines()
              if l.strip() and not l.startswith("#")]
    for name in series:
        text = (d / name).read_text(encoding="latin-1")
        files, cur = {}, None
        for l in text.splitlines():
            m = re.match(r"^\+\+\+ \S+?/(\S+)", l)
            if m:
                cur = m.group(1)
                files.setdefault(cur, [0, 0])
            elif cur and l.startswith("+") and not l.startswith("+++"):
                files[cur][0] += 1
            elif cur and l.startswith("-") and not l.startswith("---"):
                files[cur][1] += 1
        first = True
        for f, (a, r) in files.items():
            label = f"\\patch{{{mark}{tex(name[:4])}}}" if first else ""
            rows.append(f"{label} & \\file{{{tex(f)}}} & +{a} & $-${r}\\\\")
            first = False
        rows.append("\\addlinespace[2pt]")
    return rows


if __name__ == "__main__":
    files_table()
    patches_table()
    print("tables written")
