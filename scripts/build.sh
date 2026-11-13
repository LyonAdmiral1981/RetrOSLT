#!/bin/sh
# Builds RetrOS/LT: MSDOS.SYS, IO.SYS and COMMAND.COM into build/OUTPUT,
# with Microsoft's MASM 5.10 and LINK 3.65 (MIT, from the pinned MS-DOS 4.0
# tools) in DOSBox-X.      sh scripts/build.sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W="$ROOT/build/work"
rm -rf "$W"; mkdir -p "$W" "$ROOT/build/OUTPUT"
python3 "$ROOT/scripts/prep.py" "$W" >/dev/null
S="$W/SRC"
KERNEL="MSDOS MSCODE DOSMES MISC GETSET DIRCALL ALLOC DEV DIR DISK FAT ROM STDBUF STDCALL STDCTRLC STDFCB STDPROC STDIO TIME XENIX XENIX2"
COMMAND="COMMAND RUCODE RDATA INIT UINIT TCODE TCODE2 TCODE3 TCODE4 TCODE5 TUCODE COPY COPYPROC CPARSE TDATA TSPC"
BIOS="BIOS SYSINIT SYSIMES"
crlf() { sed 's/$/\r/'; }
{
  echo "@ECHO OFF"
  echo "ECHO RUNNING> STAGE.TXT"
  for m in $KERNEL $COMMAND $BIOS; do
    echo "T:\\MASM $m; >> ASM.LOG"
  done
  echo "T:\\LINK @MSDOS.LNK > LINK.LOG"
  echo "T:\\LINK @COMMAND.LNK >> LINK.LOG"
  echo "T:\\LINK @IO.LNK >> LINK.LOG"
  echo "T:\\EXE2BIN MSDOS.EXE MSDOS.SYS >> LINK.LOG"
  echo "T:\\EXE2BIN COMMAND.EXE COMMAND.COM >> LINK.LOG"
  echo "T:\\EXE2BIN IO.EXE IO.SYS < BASE.TXT >> LINK.LOG"
  echo "ECHO DONE> STAGE.TXT"
} | crlf > "$S/BUILD.BAT"
lnk() {  # name, modules...: a LINK response file, lines under 100 characters
  n=$1; shift
  python3 - "$@" <<'PY' | crlf
import sys
mods, line, out = sys.argv[1:], "", []
for m in mods:
    if len(line) + len(m) > 70:
        out.append(line + "+"); line = ""
    line += ("+" if line else "") + m
out.append(line)
print("\n".join(out))
PY
  printf '%s.EXE\r\n%s.MAP/M;\r\n' "$n" "$n"
}
lnk MSDOS $KERNEL > "$S/MSDOS.LNK"
lnk COMMAND $COMMAND > "$S/COMMAND.LNK"
lnk IO $BIOS > "$S/IO.LNK"
printf '70\r\n' > "$S/BASE.TXT"
sh "$ROOT/scripts/dosrun.sh" "$S" BUILD.BAT 15
for f in ASM.LOG LINK.LOG; do tr -d '\r' < "$S/$f" > "$ROOT/build/$f"; done
grep -E "^[A-Z0-9_]+\.ASM\([0-9]+\): (error|warning)" "$ROOT/build/ASM.LOG" | grep -v A4016 || true
grep -iE "error|unresolved|warning L" "$ROOT/build/LINK.LOG" | grep -v L4021 || true
for f in MSDOS.SYS IO.SYS COMMAND.COM; do
  if [ -f "$S/$f" ]; then cp "$S/$f" "$ROOT/build/OUTPUT/"; else echo "missing $f"; fi
done
ls -l "$ROOT/build/OUTPUT"
