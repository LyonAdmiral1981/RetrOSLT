"""Runs BASIC from the RetrOS/LT diskettes under QEMU: BASIC /ROM, then a
BASIC program that checks itself (arithmetic, strings, files, PLAY, the
screen, graphics, GET and PUT, error trapping) and says what it found.

    python3 tests/basic_test.py        (after scripts/mkinstall.py)

Prints BASIC-TEST OK at the end.
"""
import shutil, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from qpc import PC

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / "build" / "btest"
shutil.rmtree(W, ignore_errors=True); W.mkdir(parents=True)
dos = W / "DOS.IMG"; sup = W / "SUP.IMG"
shutil.copy(ROOT / "build/install/RETROS-LT-DOS.IMG", dos)
shutil.copy(ROOT / "build/install/RETROS-LT-SUPPLEMENTAL.IMG", sup)

PROG = r'''10 OPEN "B:RESULT.TXT" FOR OUTPUT AS #1:F=0
20 IF 2+2<>4 OR 7\2<>3 OR 7 MOD 3<>1 OR ABS(SQR(16)-4)>.0001 THEN F=F+1:PRINT #1,"ARITHMETIC"
30 A$="RETROS":IF LEFT$(A$,3)<>"RET" OR INSTR(A$,"OS")<>5 OR LEN(A$+A$)<>12 THEN F=F+1:PRINT #1,"STRINGS"
40 OPEN "B:T.DAT" FOR OUTPUT AS #2:PRINT #2,"ONE";",";123:CLOSE #2
50 OPEN "B:T.DAT" FOR INPUT AS #2:INPUT #2,B$,N:CLOSE #2:IF B$<>"ONE" OR N<>123 THEN F=F+1:PRINT #1,"FILES"
60 PLAY "MF T255 L64 O3 C>C<C"
70 CLS:LOCATE 5,10:PRINT "X";:IF SCREEN(5,10)<>88 OR CSRLIN<>5 OR POS(0)<>11 THEN F=F+1:PRINT #1,"SCREEN"
80 SCREEN 1:CIRCLE (160,100),40,3:PAINT (160,100),2,3
90 IF POINT(160,100)<>2 OR POINT(0,0)<>0 THEN F=F+1:PRINT #1,"PAINT"
100 DIM G%(300):GET (140,80)-(180,120),G%:PUT (10,10),G%,PSET
110 IF POINT(30,30)<>2 THEN F=F+1:PRINT #1,"GET/PUT"
120 SCREEN 0:WIDTH 80
130 ON ERROR GOTO 200:ERROR 11
140 IF E<>11 THEN F=F+1:PRINT #1,"ON ERROR"
150 PRINT #1,"FAILURES";F:CLOSE
160 IF F=0 THEN PRINT "BASIC-TEST OK" ELSE PRINT "BASIC-TEST FAILED"
170 END
200 E=ERR:RESUME NEXT
'''
(W / "BTEST.BAS").write_bytes(PROG.replace("\n", "\r\n").encode() + b"\x1a")
subprocess.run(["mcopy", "-i", str(sup), str(W / "BTEST.BAS"), "::"], check=True,
               env={"MTOOLS_SKIP_CHECK": "1", "PATH": "/usr/bin:/bin"})

pc = PC(a=str(dos), b=str(sup))
try:
    pc.wait("Enter new date"); time.sleep(0.5); pc.type("\n")
    pc.wait("Enter new time"); time.sleep(0.5); pc.type("\n")
    pc.wait("Press Enter to continue"); time.sleep(0.5); pc.key("esc")
    pc.wait("A>", 30)
    pc.type("B:\n"); pc.wait("B>", 30)
    pc.type("BASIC /ROM\n"); pc.wait("No ROM BASIC in this computer", 30)
    pc.type("BASIC BTEST\n")
    s = pc.wait("BASIC-TEST", 120)
    time.sleep(1)
    pc.type("SYSTEM\n"); pc.wait("B>", 30)
    pc.type("TYPE RESULT.TXT\n"); s = pc.wait("FAILURES", 30)
    print(s)
    ok = "FAILURES 0" in s.replace("  ", " ")
    print("BASIC-TEST OK" if ok else "BASIC-TEST FAILED")
finally:
    pc.quit()
