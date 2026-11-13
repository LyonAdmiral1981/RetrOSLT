"""Finds the lines each listing in the RetrOS/LT Guide to Engineering shows.
(After the RetrOS/x86, Extended Magic and MagicWorks Guides to Engineering.)

The book never copies code into itself. Each listing is named in
listings.txt with the file it comes from and two patterns: the first line
that matches the start pattern opens the listing, and the first line from
there on that matches the end pattern closes it (or "+N" takes N lines in
all). This writes listings.gen.tex, which the book reads, and one file of
lines for each listing in listings/, so the listings always show the code
as it is and are numbered as the file is.

A file is named from the top of the repository, or, for a file of the
MS-DOS 2 source as RetrOS/LT builds it, as lt:NAME (the tree
scripts/prep.py makes: the published source, cleaned, with the series
applied and src/ added).

If a pattern no longer matches, because the code it pointed at has changed,
the build stops and says which listing, so the text around it can be
checked too.

    python3 listings.py            (run by build.sh)
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LANG = {".ASM": "Asm", ".INC": "Asm", ".asm": "Asm", ".py": "Py", ".sh": "Shell",
        ".lua": "Lua", ".patch": "Plain", ".TXT": "Plain", "": "Plain"}


def lt_tree(work):
    """The source as RetrOS/LT builds it, made once per run."""
    tree = work / "SRC"
    if not tree.exists():
        r = subprocess.run([sys.executable, str(ROOT / "scripts" / "prep.py"), str(work)],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit("listings.py: scripts/prep.py failed:\n" + r.stdout + r.stderr)
    return tree


def find(lines, start, end, name):
    s = next((i for i, l in enumerate(lines) if re.search(start, l)), None)
    if s is None:
        sys.exit(f"listings.txt: {name}: no line matches the start pattern {start!r}")
    if re.fullmatch(r"\+\d+", end):
        e = s + int(end[1:]) - 1
    else:
        e = next((i for i in range(s, len(lines)) if re.search(end, lines[i])), None)
        if e is None:
            sys.exit(f"listings.txt: {name}: nothing after line {s + 1} matches the end pattern {end!r}")
    if e >= len(lines):
        sys.exit(f"listings.txt: {name}: runs past the end of the file")
    return s + 1, e + 1


def tex(s):
    return s.replace("\\", "/").replace("_", "\\_")


def main():
    out, seen, total = [], set(), 0
    outdir = HERE / "listings"
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir()
    with tempfile.TemporaryDirectory(prefix="roslst") as tmp:
        work = Path(tmp)
        for n, raw in enumerate((HERE / "listings.txt").read_text().splitlines(), 1):
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            parts = [p.strip() for p in raw.split(" | ")]
            if len(parts) != 4:
                sys.exit(f"listings.txt, line {n}: want  name | file | start pattern | end pattern")
            name, path, start, end = parts
            if name in seen:
                sys.exit(f"listings.txt, line {n}: {name} is named twice")
            seen.add(name)
            m = re.fullmatch(r"lt:(.+)", path)
            if m:
                f = lt_tree(work) / m.group(1)
                show = f"{tex(m.group(1))}, as built"
            else:
                f = ROOT / path
                show = tex(path)
            if not f.exists():
                sys.exit(f"listings.txt: {name}: no file {path}")
            lines = f.read_text(encoding="cp437").replace("\r", "").replace("\x1a", "").splitlines()
            a, b = find(lines, start, end, name)
            total += b - a + 1
            lang = LANG.get(f.suffix, "Plain")
            # The lines go into a file of their own, which the book prints with
            # the source's numbering: listings mishandles characters outside
            # ASCII in lines it is told to skip.
            body = "\n".join(l.expandtabs(8) for l in lines[a - 1:b]) + "\n"
            (outdir / f"{name}.txt").write_text(body, encoding="utf-8")
            out.append(f"\\roslstdef{{{name}}}{{{path}}}{{{a}}}{{{b}}}{{{lang}}}{{{show}}}")
    (HERE / "listings.gen.tex").write_text("\n".join(out) + "\n")
    print(f"{len(out)} listings, {total:,} lines")


if __name__ == "__main__":
    main()
