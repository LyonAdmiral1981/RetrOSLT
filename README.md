# RetrOS/LT

RetrOS/LT ("LiTe") is a disk operating system for the IBM Personal Computer
and Personal Computer XT, built from Microsoft's MS-DOS 2.x source code
(MIT License) and meant to be indistinguishable, on that hardware, from
IBM PC DOS 2.10. It reports DOS version 2.10.

It is a sibling of RetrOS/86 and RetrOS/286 (the RetrOS/x86 family, built
from MS-DOS 4.0), not a replacement for them.

## Status

Work in progress. The kernel (MSDOS.SYS) and COMMAND.COM build from
Microsoft's source with the 1988 Microsoft tools; IO.SYS, the BIOS
interface for the IBM PC, and the boot sector are new. RetrOS/LT starts on
MAME's IBM PC 5150 with IBM's October 1982 ROM BIOS and runs commands.

## Layout

- `upstream/msdos` Microsoft's MS-DOS repository, pinned (submodule)
- `patches/` RetrOS/LT's changes to the 2.x source, in `series` order
- `src/` RetrOS/LT's own sources for the system: `BIOS.ASM` (IO.SYS) and
  `IO.ASM` (the kernel's console functions, missing from the published
  source and reconstructed)
- `boot/BOOT.ASM` the boot sector (NASM)
- `scripts/` `build.sh` (DOSBox-X), `prep.py`, `mkboot.py` (a startup
  diskette image), `dosrun.sh`
- `tests/` `qpc.py` (QEMU), `mame5150/` (the IBM PC's own BIOS)

## Building

    git submodule update --init
    sh scripts/build.sh                 # build/OUTPUT: IO.SYS MSDOS.SYS COMMAND.COM
    python3 scripts/mkboot.py build/A.IMG
    python3 tests/qpc.py build/A.IMG --type '\n' --type '\n' --type 'DIR\n'

Needs DOSBox-X, NASM, mtools, Python 3 and patch; QEMU or MAME to run it.

## License

Microsoft's code is Copyright Microsoft Corporation, MIT License (see
upstream/msdos/LICENSE). RetrOS/LT's own files are Copyright The Lyon
Mountain Company, Republic Lyon Mountain Corporation 2026.
