#!/bin/sh
# Builds BASICA.EXE (Microsoft's GW-BASIC with RetrOS's IBM PC layer) with
# MASM 5.10 and LINK 3.65 in DOSBox-X, and BASIC.COM with NASM, into
# build/OUTPUT.      sh scripts/buildbasic.sh ["EDITION NAME"]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-RetrOS/LT BASIC Version 1.0}
B="$ROOT/build/work/BAS"
rm -rf "$B"; mkdir -p "$B" "$ROOT/build/OUTPUT"
python3 "$ROOT/scripts/prepbasic.py" "$B" "$NAME"
# Link order: GWDATA first (the data segment starts there); PCIO before
# ITSA86, whose code after CSEND is given back once BASIC is running; and
# BIBOOT last, since its LSTVAR ends the data segment and BASIC's program
# text begins there.
MODS="GWDATA ADVGRP BIMISC BIPRTU BIPTRG BISTRS CALL86 DSKCOM FIVEO GENGRP
GIO86 GIOCAS GIOCOM GIOCON GIODSK GIOKYB GIOLPT GIOSCN GIOTBL GWEVAL GWINIT
GWLIST GWMAIN GWRAM GWSTS IBMRES KANJ86 MACLNG MATH NEXT86 SCNDRV SCNEDT
PCIO ITSA86 BIBOOT"
crlf() { sed 's/$/\r/'; }
{
  echo "@ECHO OFF"
  for m in $MODS; do echo "T:\\MASM $m; >> ASM.LOG"; done
  echo "T:\\LINK @BASICA.LNK > LINK.LOG"
} | crlf > "$B/BUILD.BAT"
python3 - $MODS <<'PY' | crlf > "$B/BASICA.LNK"
import sys
line, out = "", []
for m in sys.argv[1:]:
    if len(line) + len(m) > 70:
        out.append(line + "+"); line = ""
    line += ("+" if line else "") + m
out.append(line)
print("\n".join(out))
print("BASICA.EXE")
print("BASICA.MAP/M;")
PY
sh "$ROOT/scripts/dosrun.sh" "$B" BUILD.BAT 10
for f in ASM.LOG LINK.LOG; do tr -d '\r' < "$B/$f" > "$ROOT/build/BAS-$f"; done
# Expected: MASM's warnings for symbols named like 8087 instructions
# (A4016, A4057 "reserved word") in Microsoft's modules, and LINK's
# "no stack segment" (BIBOOT sets its own).
grep -E "error A[0-9]" "$ROOT/build/BAS-ASM.LOG" || true
grep -iE "error|unresolved" "$ROOT/build/BAS-LINK.LOG" || true
cp "$B/BASICA.EXE" "$ROOT/build/OUTPUT/"
nasm -f bin -o "$ROOT/build/OUTPUT/BASIC.COM" "$ROOT/basic/BASIC.ASM"
ls -l "$ROOT/build/OUTPUT/BASICA.EXE" "$ROOT/build/OUTPUT/BASIC.COM"
