#!/bin/sh
# Builds the RetrOS/LT Guide to Engineering, in the same three editions as
# the Guide to Operations, whose page design (../guide/rosguide.sty), index
# style and figures it shares:
#   single  RetrOS-LT-Guide-to-Engineering.pdf             one-sided, US Letter
#   duplex  RetrOS-LT-Guide-to-Engineering-Two-Sided.pdf   two-sided, US Letter
#   shop    RetrOS-LT-Guide-to-Engineering-Print-Shop.pdf  two-sided, 1/8-inch bleed
# Needs XeLaTeX (TeX Live) with the TeX Gyre fonts, makeindex, Courier 10
# Pitch, Python 3 and patch, and the upstream/msdos submodule, from which
# the listings are taken.   sh docs/engineering/build.sh
# MODES="single" builds only the one-sided edition.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
# The build this edition describes: the last commit outside docs/, as
# R + YY.MM.DD.HH.MM, Eastern time, the numbering of the house's other guides.
WHEN=$(git -C "$HERE/../.." log -1 --format=%ct -- . ':(exclude)docs' 2>/dev/null)
[ -n "$WHEN" ] || WHEN=$(date +%s)
REL=$(TZ=America/New_York date -d "@$WHEN" +R%y.%m.%d.%H.%M 2>/dev/null || TZ=America/New_York date -r "$WHEN" +R%y.%m.%d.%H.%M)
printf '\\newcommand\\release{%s}\n' "$REL" > release.tex
# Where each listing's lines are in the source as each edition builds it
python3 listings.py
python3 tables.py
export TEXINPUTS="$HERE//:$HERE/../guide//:"
build() {   # mode, output file
    mode=$1; job="engineering-$1"
    run() { xelatex -interaction=nonstopmode -halt-on-error -jobname="$job" "\\def\\mwmode{$mode}\\input{engineering}" > "$job.build.log" 2>&1 || { tail -40 "$job.build.log"; exit 1; }; }
    run
    makeindex -q -s ../guide/rosindex.ist "$job.idx"
    run
    run
    mv "$job.pdf" "$2"
    echo "built $2"
}
for m in ${MODES:-single duplex shop}; do
    case $m in
        single) build single RetrOS-LT-Guide-to-Engineering.pdf ;;
        duplex) build duplex RetrOS-LT-Guide-to-Engineering-Two-Sided.pdf ;;
        shop)   build shop   RetrOS-LT-Guide-to-Engineering-Print-Shop.pdf ;;
    esac
done
echo "for release $REL"
