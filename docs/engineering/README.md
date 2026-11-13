# RetrOS/LT Guide to Engineering

The companion to the *RetrOS/LT Guide to Operations*: how RetrOS/LT is
made from Microsoft's MS-DOS 2 source, how it starts, how the IBM commands
were written again, how Install and the diskettes work, and how it is
built and tested. After the RetrOS/x86, Extended Magic and MagicWorks
Guides to Engineering. It shares the Guide to Operations' page design
(`../guide/rosguide.sty`, Board G "Twenty Lines"), index style and figures,
and adds listings, "In Plain Words" panels for readers who do not program,
and engineering notes (`rosengineering.sty`). Three editions, all US
Letter:

- `RetrOS-LT-Guide-to-Engineering.pdf`: one-sided
- `RetrOS-LT-Guide-to-Engineering-Two-Sided.pdf`: two-sided
- `RetrOS-LT-Guide-to-Engineering-Print-Shop.pdf`: two-sided, with bleed

    sh docs/engineering/build.sh            (MODES=single for one edition)

Needs XeLaTeX and makeindex (TeX Live), the TeX Gyre fonts, Courier 10
Pitch, Python 3, `patch`, and the `upstream/msdos` submodule.

## Listings

The listings are never pasted into the book. `listings.txt` names each one
by its file and by patterns matching its first and last lines. A file of
Microsoft's source is named `lt:NAME`: `listings.py` runs
`scripts/prep.py` into a temporary directory, as the build does, and takes
the lines from the result. If a pattern no longer matches, the build stops
and names the listing, so the text about it gets reread.

`tables.py` writes Appendix A's file list with line counts and Appendix B's
per-patch, per-file table. It stops if a file in `src/`, `boot/`, `cmd/`,
`dev/`, `install/`, `scripts/`, `tests/` or `dist/` is missing from
Appendix A's list.
