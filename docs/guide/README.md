# RetrOS/LT Guide to Operations

The user's manual for RetrOS/LT, from the same house as the RetrOS/x86,
MagicWorks and Extended Magic guides: the structure of IBM's Personal
Computer manuals (numbered Sections, section-page numbering 3-12, side
headings, a contents list at the head of each Section) and the Lyon
Mountain Company cover. The motif is Board G, "Twenty Lines": the 8088's
twenty address lines, A19 to A0, as a band of twenty green cells, and on
the cover the 8088 in its 40-pin package (proofs: `../proofs`).

Three editions are built from the same source, all US Letter:

- `RetrOS-LT-Guide-to-Operations.pdf`: one-sided, for printing at home
- `RetrOS-LT-Guide-to-Operations-Two-Sided.pdf`: two-sided; every Section
  starts on a front page, and empty back pages say so
- `RetrOS-LT-Guide-to-Operations-Print-Shop.pdf`: two-sided, with 1/8-inch
  bleed all round, 8 3/4 x 11 1/4 inches, to be trimmed to 8 1/2 x 11

    sh docs/guide/build.sh

Needs XeLaTeX and makeindex (TeX Live), the TeX Gyre fonts and Courier 10
Pitch.

- `guide.tex` the book; `front.tex`, `s1-...s7-*.tex`, `appendixes.tex`,
  `back.tex` its parts (glossary, index, quick reference card, reader's
  comment form)
- `rosguide.sty` the page design, including the address band
  (`\addressband`) and the 8088 (`\dipchip`); `rosindex.ist` the index style
- `diskfiles.tex` the table of Appendix A, written by
  `python3 diskfiles.py ../../build/install > diskfiles.tex` from the two
  diskettes `scripts/mkinstall.py` makes; regenerate it when they change
- `../../dist/NOTICE.TXT` and `../../dist/LICENSE.TXT`, printed in
  Appendix D

The screens shown are those of RetrOS/LT under QEMU and on MAME's IBM PC
5150; the messages are the programs' own.
