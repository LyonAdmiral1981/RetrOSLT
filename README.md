# RetrOS/LT

RetrOS/LT ("LiTe") is a disk operating system for the IBM Personal Computer
and Personal Computer XT, built from Microsoft's MS-DOS 2.x source code
(MIT License) and meant to be indistinguishable, on that hardware, from
IBM PC DOS 2.10. It reports DOS version 2.10.

It is a sibling of RetrOS/86 and RetrOS/286 (the RetrOS/x86 family, built
from MS-DOS 4.0), not a replacement for them.

## Status

Work in progress. The kernel (RETDOS.COM) and COMMAND.COM build from
Microsoft's source with the 1988 Microsoft tools; RETBIO.COM, the BIOS
interface for the IBM PC, and the boot sector are new. RetrOS/LT starts on
MAME's IBM PC 5150 with IBM's October 1982 ROM BIOS, and on the XT's fixed
disk.

The commands are PC DOS 2.10's set. Those in Microsoft's 2.x source build
from it (CHKDSK, DEBUG, EDLIN, EXE2BIN, FC, FIND, MORE, PRINT, RECOVER,
SORT, SYS, FORMAT); LINK is Microsoft's 2.00 linker as released. The ones
IBM wrote are written new, to behave as IBM's do: FDISK, DISKCOPY,
DISKCOMP, COMP, TREE, ASSIGN, MODE, GRAPHICS, BACKUP, RESTORE and ANSI.SYS.

RetrOS/LT comes as PC DOS 2.10 did, on two single-sided 180 KB diskettes
that any IBM PC or PC XT drive reads: the DOS diskette, which starts the
computer and holds the system, the commands and Install, and the
Supplemental Programs diskette (DEBUG, LINK, EXE2BIN). Install, adapted
from RetrOS/x86's, partitions, formats and fills the fixed disk, asking
first. FC, from Microsoft's source (PC DOS 2.10 does not have it), comes as an
extra.

The *Guide to Operations* (`docs/guide`) and *Guide to Engineering*
(`docs/engineering`) are in three editions each: one-sided, two-sided,
and for a print shop.

## Layout

- `upstream/msdos` Microsoft's MS-DOS repository, pinned (submodule)
- `patches/` RetrOS/LT's changes to the 2.x source, in `series` order
- `src/` RetrOS/LT's own sources for the system: `BIOS.ASM` (RETBIO.COM),
  `IO.ASM` (the kernel's console functions, missing from the published
  source and reconstructed) and `IBMFOR.ASM` (FORMAT's IBM PC part)
- `boot/` the boot sector and master boot record (NASM)
- `cmd/` the commands written for RetrOS/LT (NASM)
- `dev/` ANSI.SYS (NASM)
- `install/INSTALL.ASM` Install (NASM)
- `dist/` `LICENSE.TXT` (the RetrOS/LT License) and `NOTICE.TXT`
  (Microsoft's), which go on the DOS diskette
- `scripts/` `build.sh` (DOSBox-X), `prep.py`, `mkboot.py` (a startup
  diskette image), `mkhd.py` (a fixed disk image), `mkinstall.py` (the
  two distribution diskettes), `dosrun.sh`
- `tests/` `qpc.py` (QEMU), `hd_test.py` (FDISK, FORMAT and starting from
  the fixed disk), `install_test.py` (Install onto an empty fixed disk), `mame5150/` (the IBM PC's own BIOS, which you supply)

## Building

    git submodule update --init
    sh scripts/build.sh                 # build/OUTPUT: the system and commands
    python3 scripts/mkinstall.py        # build/install: the two diskettes
    python3 tests/install_test.py
    python3 scripts/mkboot.py build/A.IMG
    python3 tests/qpc.py build/A.IMG --type '\n' --type '\n' --type 'DIR\n'

Needs DOSBox-X, NASM, mtools, Python 3 and patch; QEMU or MAME to run it.
The assembler and linker are Microsoft's, from the MS-DOS 4.0 tree in the
same submodule.

## License

Microsoft's code is Copyright Microsoft Corporation, MIT License (see
upstream/msdos/LICENSE). RetrOS/LT's own files are Copyright The Lyon
Mountain Company, Republic Lyon Mountain Corporation 2026.
