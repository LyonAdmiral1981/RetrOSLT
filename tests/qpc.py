"""A PC in QEMU, driven through its monitor: for quick tests under QEMU's
own BIOS. (tests/mame5150 runs the IBM PC's.)

    from qpc import PC
    pc = PC(a="A.IMG", hd="C.IMG")
    pc.wait("A>")
    pc.type("DIR\\n")
    print(pc.screen())

Run directly, it starts from A.IMG and prints the screen:
    python3 tests/qpc.py A.IMG [--hd C.IMG] [--b B.IMG] [--wait S] [--type TEXT]...
"""
import argparse, os, re, subprocess, time

KEYS = {"\n": "ret", " ": "spc", ".": "dot", ":": "shift-semicolon", "\\": "backslash",
        "/": "slash", "-": "minus", "=": "equal", "*": "shift-8", ",": "comma",
        ">": "shift-dot", "<": "shift-comma", "?": "shift-slash", "_": "shift-minus",
        ";": "semicolon", "\x1b": "esc", "\b": "backspace", "$": "shift-4", "!": "shift-1",
        "+": "shift-equal", "'": "apostrophe", '"': "shift-apostrophe", "|": "shift-backslash",
        "%": "shift-5", "&": "shift-7", "(": "shift-9", ")": "shift-0", "#": "shift-3",
        "@": "shift-2", "^": "shift-6", "\t": "tab"}


class PC:
    def __init__(self, a=None, b=None, hd=None, hd2=None, boot="a", mem=4, lpt=None):
        cmd = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", str(mem),
               "-display", "none", "-monitor", "stdio", "-boot", f"order={boot}"]
        if lpt:
            cmd += ["-parallel", f"file:{lpt}"]
        if a:
            cmd += ["-drive", f"file={a},if=floppy,index=0,format=raw"]
        if b:
            cmd += ["-drive", f"file={b},if=floppy,index=1,format=raw"]
        for i, h in enumerate((hd, hd2)):
            if not h:
                continue
            # FILE or FILE:CYLS:HEADS:SECTORS (default: the XT's 306:4:17)
            f, *g = h.split(":")
            c, hh, ss = (g + ["306", "4", "17"][len(g):]) if g else ("306", "4", "17")
            cmd += ["-drive", f"file={f},if=none,id=hd{i},format=raw",
                    "-device", f"ide-hd,drive=hd{i},bus=ide.0,unit={i},cyls={c},heads={hh},secs={ss},bios-chs-trans=none"]
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT)
        os.set_blocking(self.p.stdout.fileno(), False)

    def cmd(self, line, pause=0.3):
        self.p.stdin.write((line + "\n").encode())
        self.p.stdin.flush()
        time.sleep(pause)
        data = b""
        while True:
            chunk = self.p.stdout.read()
            if not chunk:
                break
            data += chunk
        return data.decode("latin-1")

    def screen(self):
        out = self.cmd("xp /2000hx 0xb8000", 0.6)
        words = [int(x, 16) for x in re.findall(r"0x([0-9a-f]{4})\b(?!:)", out)][-2000:]
        text = "".join(chr(w & 255) if 32 <= (w & 255) < 127 else " " for w in words)
        rows = [text[i:i + 80].rstrip() for i in range(0, len(text), 80)]
        while rows and not rows[-1]:
            rows.pop()
        return "\n".join(rows)

    def wait(self, text, timeout=60):
        end = time.time() + timeout
        while time.time() < end:
            s = self.screen()
            if text in s:
                return s
            time.sleep(0.5)
        raise SystemExit(f"FAIL: never saw {text!r}. Screen:\n{self.screen()}")

    def key(self, name):
        self.cmd("sendkey " + name, 0.08)

    def type(self, text):
        for ch in text:
            if ch.isalpha() and ch.isupper():
                self.key("shift-" + ch.lower())
            else:
                self.key(KEYS.get(ch, ch.lower()))

    def quit(self):
        try:
            self.cmd("quit")
        except OSError:
            pass
        self.p.wait(timeout=10)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("--b")
    ap.add_argument("--hd")
    ap.add_argument("--wait", type=float, default=4)
    ap.add_argument("--type", action="append", default=[])
    o = ap.parse_args()
    pc = PC(a=o.a, b=o.b, hd=o.hd)
    time.sleep(o.wait)
    for t in o.type:
        pc.type(t.encode().decode("unicode_escape"))
        time.sleep(o.wait)
    print(pc.screen())
    pc.quit()
