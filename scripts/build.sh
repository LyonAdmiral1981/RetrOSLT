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
# The commands written for NASM (cmd/*.ASM), and the master boot record
# FDISK writes (the code part of boot/MBR.ASM: MBRCODE.INC)
nasm -f bin -o "$ROOT/build/MBR.BIN" "$ROOT/boot/MBR.ASM"
python3 - "$ROOT/build/MBR.BIN" > "$ROOT/build/MBRCODE.INC" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()[:0x1BE]
print("mbrcode:")
for i in range(0, len(b), 16):
    print("        db      " + ",".join("0%02Xh" % x for x in b[i:i+16]))
PY
for f in "$ROOT"/cmd/*.ASM; do
  n=$(basename "$f" .ASM)
  nasm -f bin -i "$ROOT/build/" -i "$ROOT/cmd/" -o "$ROOT/build/OUTPUT/$n.COM" "$f"
done
# The device drivers (dev/*.ASM), to .SYS
for f in "$ROOT"/dev/*.ASM; do
  n=$(basename "$f" .ASM)
  nasm -f bin -i "$ROOT/dev/" -o "$ROOT/build/OUTPUT/$n.SYS" "$f"
done
# The boot sector, for FORMAT and SYS to write: BOOTSECT.INC
nasm -f bin -o "$ROOT/build/BOOT.BIN" "$ROOT/boot/BOOT.ASM"
python3 - "$ROOT/build/BOOT.BIN" > "$S/BOOTSECT.INC" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
print("; The RetrOS/LT boot sector (boot/BOOT.ASM), made by build.sh\r")
for i in range(0, 512, 16):
    print(("BOOT    DB      " if i == 0 else "        DB      ") + ",".join("0%02XH" % x for x in b[i:i+16]) + "\r")
PY
KERNEL="MSDOS MSCODE DOSMES MISC GETSET DIRCALL ALLOC DEV DIR DISK FAT ROM STDBUF STDCALL STDCTRLC STDFCB STDPROC STDIO TIME XENIX XENIX2"
COMMAND="COMMAND RUCODE RDATA INIT UINIT TCODE TCODE2 TCODE3 TCODE4 TCODE5 TUCODE COPY COPYPROC CPARSE TDATA TSPC"
BIOS="BIOS SYSINIT SYSIMES"
# The commands: NAME:TYPE:MODULES (in link order)[:LINK SWITCHES]. SORT takes
# what memory it needs itself, so it must be loaded with none to spare.
CMDS="CHKDSK:COM:CHKDSK,CHKPROC,CHKMES
DEBUG:COM:DEBUG,DEBCOM1,DEBCOM2,DEBUASM,DEBASM,DEBCONST,DEBDATA,DEBMES
EDLIN:COM:EDLIN,EDLPROC,EDLMES
EXE2BIN:EXE:EXE2BIN,EXEMES
FC:EXE:FC,FCMES
FIND:EXE:FIND,FINDMES
MORE:COM:MORE,MOREMES
PRINT:COM:PRINT
RECOVER:COM:RECOVER,RECMES
SORT:EXE:SORT,SORTMES:/CP:1
SYS:COM:SYS,SYSMES
FORMAT:COM:FORMAT,FORMES,IBMFOR"
CMDMODS=$(echo "$CMDS" | cut -d: -f3 | tr ',\n' '  ' | tr -s ' ' '\n' | sort -u | tr '\n' ' ')
crlf() { sed 's/$/\r/'; }
{
  echo "@ECHO OFF"
  echo "ECHO RUNNING> STAGE.TXT"
  for m in $KERNEL $COMMAND $BIOS $CMDMODS; do
    echo "T:\\MASM $m; >> ASM.LOG"
  done
  echo "T:\\LINK @MSDOS.LNK > LINK.LOG"
  echo "T:\\LINK @COMMAND.LNK >> LINK.LOG"
  echo "T:\\LINK @IO.LNK >> LINK.LOG"
  echo "T:\\EXE2BIN MSDOS.EXE MSDOS.SYS >> LINK.LOG"
  echo "T:\\EXE2BIN COMMAND.EXE COMMAND.COM >> LINK.LOG"
  echo "T:\\EXE2BIN IO.EXE IO.SYS < BASE.TXT >> LINK.LOG"
  echo "$CMDS" | while IFS=: read n t mods sw; do
    echo "T:\\LINK @$n.LNK >> LINK.LOG"
    [ "$t" = COM ] && echo "T:\\EXE2BIN $n.EXE $n.COM >> LINK.LOG"
  done
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
  printf '%s.EXE\r\n%s.MAP/M%s;\r\n' "$n" "$n" "${LNKSW:-}"
}
lnk MSDOS $KERNEL > "$S/MSDOS.LNK"
lnk COMMAND $COMMAND > "$S/COMMAND.LNK"
lnk IO $BIOS > "$S/IO.LNK"
echo "$CMDS" | while IFS=: read n t mods sw; do LNKSW="${sw:-}" lnk $n $(echo $mods | tr , ' ') > "$S/$n.LNK"; done
printf '70\r\n' > "$S/BASE.TXT"
sh "$ROOT/scripts/dosrun.sh" "$S" BUILD.BAT 15
for f in ASM.LOG LINK.LOG; do tr -d '\r' < "$S/$f" > "$ROOT/build/$f"; done
grep -E "^[A-Z0-9_]+\.ASM\([0-9]+\): (error|warning)" "$ROOT/build/ASM.LOG" | grep -v A4016 || true
grep -iE "error|unresolved|warning L" "$ROOT/build/LINK.LOG" | grep -v L4021 || true
for f in MSDOS.SYS IO.SYS COMMAND.COM $(echo "$CMDS" | awk -F: '{print $1"."$2}'); do
  if [ -f "$S/$f" ]; then cp "$S/$f" "$ROOT/build/OUTPUT/"; else echo "missing $f"; fi
done
ls -l "$ROOT/build/OUTPUT"
