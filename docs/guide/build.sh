#!/bin/sh
# Builds the RetrOS/LT Guide to Operations in three editions, as the
# MagicWorks Guide to Operations is built (see that book's build.sh):
#   single  RetrOS-LT-Guide-to-Operations.pdf             one-sided, US Letter
#   duplex  RetrOS-LT-Guide-to-Operations-Two-Sided.pdf   two-sided, US Letter
#   shop    RetrOS-LT-Guide-to-Operations-Print-Shop.pdf  two-sided, 1/8-inch bleed,
#           8 3/4 x 11 1/4 inches trimmed to 8 1/2 x 11
# Needs XeLaTeX (TeX Live) with the TeX Gyre fonts, makeindex, and the
# Courier 10 Pitch font.  sh docs/guide/build.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
# The build this edition describes: the last commit outside docs/, as
# R + YY.MM.DD.HH.MM, Eastern time, the numbering of the house's other guides.
WHEN=$(git -C "$HERE/../.." log -1 --format=%ct -- . ':(exclude)docs' 2>/dev/null)
[ -n "$WHEN" ] || WHEN=$(date +%s)
REL=$(TZ=America/New_York date -d "@$WHEN" +R%y.%m.%d.%H.%M 2>/dev/null || TZ=America/New_York date -r "$WHEN" +R%y.%m.%d.%H.%M)
printf '\\newcommand\\release{%s}\n' "$REL" > release.tex
build() {   # mode, output file
    mode=$1; job="guide-$1"
    run() { xelatex -interaction=nonstopmode -halt-on-error -jobname="$job" "\\def\\mwmode{$mode}\\input{guide}" > "$job.build.log" 2>&1 || { tail -40 "$job.build.log"; exit 1; }; }
    run
    makeindex -q -s rosindex.ist "$job.idx"
    run
    run
    mv "$job.pdf" "$2"
    echo "built $2"
}
build single RetrOS-LT-Guide-to-Operations.pdf
build duplex RetrOS-LT-Guide-to-Operations-Two-Sided.pdf
build shop   RetrOS-LT-Guide-to-Operations-Print-Shop.pdf
echo "for release $REL"
