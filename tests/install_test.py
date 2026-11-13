"""Installs RetrOS/LT from its two diskettes onto an empty XT fixed disk under
QEMU, as a person would, then starts from the fixed disk and uses it.

    python3 tests/install_test.py        (after scripts/mkinstall.py)

Prints INSTALL-TEST OK at the end.
"""
import os, shutil, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from qpc import PC

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / "build" / "itest"
shutil.rmtree(W, ignore_errors=True); W.mkdir(parents=True)
dos = W / "DOS.IMG"; sup = W / "SUP.IMG"; hd = W / "C.IMG"
shutil.copy(ROOT / "build/install/RETROS-LT-DOS.IMG", dos)
shutil.copy(ROOT / "build/install/RETROS-LT-SUPPLEMENTAL.IMG", sup)
hd.write_bytes(bytes(306 * 4 * 17 * 512))

pc = PC(a=str(dos), hd=str(hd), boot="ac")


def step(want, keys, timeout=60):
    pc.wait(want, timeout)
    time.sleep(0.5)
    pc.type(keys)


def dates():
    step("Enter new date", "\n")
    step("Enter new time", "\n")


try:
    # first start: partition the disk
    dates()
    step("Press Enter to continue", "\n")
    step("(Y/N)?", "Y")
    step("Press W, F or Esc", "W")
    step("must restart", " ")
    # second start: format, copy, configure
    dates()
    step("Press Enter to continue", "\n")
    step("(Y/N)?", "Y")
    step("Where should", "\n")
    step("is not formatted", "\n")
    step("FORMAT will now prepare", "\n")
    step("begin formatting", " ")
    pc.wait("Supplemental Programs diskette in", 600)
    pc.cmd(f"change floppy0 {sup}", 1)
    time.sleep(3)
    pc.type("\n")
    pc.wait("is installed on drive C:", 120)
    pc.cmd("eject floppy0", 1)
    pc.type("\n")
    # from the fixed disk
    dates()
    pc.wait("C:\\>", 30)
    seen = ""
    for c, want in (("VER\n", "DOS 2.10"), ("DEBUG\n", "-"), ("Q\n", "C:\\>"),
                    ("CLS\n", "C:\\>"), ("TYPE CONFIG.SYS\n", "DEVICE=C:\\DOS\\ANSI.SYS"),
                    ("TYPE AUTOEXEC.BAT\n", "PATH C:\\DOS"), ("CLS\n", "C:\\>"),
                    ("CHKDSK\n", "bytes free")):
        pc.type(c)
        s = pc.wait(want, 30)
    seen = s
    print(pc.screen())
    ok = True
    print("INSTALL-TEST OK" if ok else "INSTALL-TEST FAILED")
finally:
    pc.quit()
