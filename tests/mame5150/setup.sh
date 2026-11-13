#!/bin/bash
# Prepare tests/mame5150 to run: MAME's IBM PC 5150 with the real BIOS.
#
#   tests/mame5150/setup.sh BIOS_IMAGE
#
# BIOS_IMAGE is the 8 KB IBM PC BIOS 1501476 (10/27/82), from your own
# machine. It is IBM's and is not kept in this repository; it goes in
# tests/mame5150/roms/, which git ignores. The BASIC, character and
# keyboard ROMs are stand-ins of zero bytes: the tests boot from diskette
# (so BASIC is never run), read the screen from video memory (so no
# characters are drawn), and type nothing (so the keyboard's 301 error at
# power-on is expected). Needs MAME (apt install mame), mtools and nasm.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "${1:-}" ] || { echo "usage: $0 BIOS_IMAGE" >&2; exit 1; }
sha=$(sha1sum "$1" | cut -d' ' -f1)
[ "$sha" = 40fce6a94dda4328a8b608c7ae2f39d1dc688af4 ] || echo "warning: not the known 1501476 image ($sha)" >&2
mkdir -p "$HERE/roms/ibm5150" "$HERE/roms/cga" "$HERE/roms/kb_pc83" "$HERE/cfg256" "$HERE/cfg640"
cp "$1" "$HERE/roms/ibm5150/1501476.u33"
for n in 5000019.u29 5000021.u30 5000022.u31 5000023.u32 5788005.u33; do head -c 8192 /dev/zero > "$HERE/roms/ibm5150/$n"; done
head -c 8192 /dev/zero > "$HERE/roms/cga/5788005.u33"
head -c 1024 /dev/zero > "$HERE/roms/kb_pc83/8048.u1"
# Memory switches. MAME's 5150 has the 16-64 KB board: 64 KB on it, the
# rest on a memory card (DSW1 "Extra RAM size": 6 = 192 KB, 18 = 576 KB).
for kb in 256:6 640:18; do
  cat > "$HERE/cfg${kb%%:*}/ibm5150.cfg" <<CFG
<?xml version="1.0"?>
<mameconfig version="10">
    <system name="ibm5150">
        <input>
            <port tag=":mb:DSW1" type="DIPSWITCH" mask="31" defvalue="18" value="${kb##*:}" />
        </input>
    </system>
</mameconfig>
CFG
done
nasm -f bin -o "$HERE/WAITSWAP.COM" "$HERE/WAITSWAP.ASM"
nasm -f bin -o "$HERE/FIXTEST.COM" "$HERE/../FIXTEST.ASM"
nasm -f bin -o "$HERE/STRESS.COM" "$HERE/../STRESS.ASM"
echo "Ready. Run tests/mame5150/test.sh SYSTEM_DIR"
