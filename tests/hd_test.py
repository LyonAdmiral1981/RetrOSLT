"""Sets up a blank fixed disk as a person would, under QEMU: FDISK (the whole
disk for DOS), restart, FORMAT C:/S/V, then starts from the fixed disk and
checks it with CHKDSK.

    python3 tests/hd_test.py [CYLS HEADS SPT]       (default: the XT's 306 4 17)
"""
import subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from qpc import PC

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / "build"
O = B / "OUTPUT"


def main():
    geo = sys.argv[1:4] if len(sys.argv) >= 4 else ["306", "4", "17"]
    c, h, s = (int(x) for x in geo)
    a, hd = B / "HDTEST-A.IMG", B / "HDTEST-C.IMG"
    subprocess.run(["python3", str(ROOT / "scripts" / "mkboot.py"), str(a)] +
                   [str(O / f) for f in ("FDISK.COM", "FORMAT.COM", "SYS.COM", "CHKDSK.COM")],
                   check=True, capture_output=True)
    (B / "AUTOEXEC.BAT").write_bytes(b"ECHO OFF\r\n")
    subprocess.run(["mcopy", "-o", "-i", str(a), str(B / "AUTOEXEC.BAT"), "::"], check=True)
    hd.write_bytes(bytes(c * h * s * 512))
    hdarg = f"{hd}:{c}:{h}:{s}"

    pc = PC(a=str(a), hd=hdarg)
    try:
        pc.wait("A>", 30)
        pc.type("FDISK\n")
        pc.wait("Enter choice", 20)
        pc.type("\n")                              # 1. Create DOS Partition
        pc.wait("entire fixed disk", 20)
        pc.type("\n")                              # Y
        pc.wait("Press Esc", 20)
        pc.key("esc")
        pc.wait("Enter choice", 20)
        pc.key("esc")
        pc.wait("restart", 20)
        pc.type(" ")
        pc.wait("A>", 60)                          # started again from A:
        pc.type("FORMAT C:/S/V\n")
        pc.wait("begin formatting", 30)
        pc.type(" ")
        pc.wait("label", 600)
        pc.type("FIXED\n")
        pc.wait("A>", 60)
        pc.type("COPY CHKDSK.COM C:\n")
        pc.wait("copied", 30)
        print(pc.screen())
    finally:
        pc.quit()

    pc = PC(hd=hdarg, boot="c")
    try:
        pc.wait("Enter new date", 60)
        pc.type("\n")
        pc.wait("Enter new time", 20)
        pc.type("\n")
        pc.wait("C>", 20)
        pc.type("CHKDSK\n")
        scr = pc.wait("bytes free", 30)
        print(scr)
    finally:
        pc.quit()
    if "Volume FIXED" not in scr:
        sys.exit("FAIL: the fixed disk did not come up as formatted")
    print("HD-TEST OK")


if __name__ == "__main__":
    main()
