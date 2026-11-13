#!/usr/bin/env python3
"""Write diskfiles.tex, the table of Appendix A, from the two RetrOS/LT
diskettes.

Usage: diskfiles.py BUILD_INSTALL_DIR > diskfiles.tex
"""
import os, re, subprocess, sys

ENV = dict(os.environ, MTOOLS_SKIP_CHECK="1")
D = {
    "RETBIO.COM": "System file: works the hardware. Hidden.",
    "RETDOS.COM": "System file: the kernel. Hidden.",
    "COMMAND.COM": "The command processor.",
    "AUTOEXEC.BAT": "Asks the date and time and runs Install. Not installed.",
    "INSTALL.COM": "The Install program. Not installed.",
    "LICENSE.TXT": "The RetrOS/LT License.",
    "NOTICE.TXT": "The notice for Microsoft's code.",
    "ANSI.SYS": "Driver: ANSI screen and keyboard control.",
    "FC.EXE": "The FC command (not in PC DOS 2.10).",
}
DISKS = (("RETROS-LT-DOS.IMG", "DOS"), ("RETROS-LT-SUPPLEMENTAL.IMG", "Supplemental"))


def listing(image):
    out = subprocess.run(["mdir", "-a", "-i", image, "::"], capture_output=True, text=True, env=ENV).stdout
    files = []
    for l in out.splitlines():
        m = re.match(r"^(\S+)\s+(\S+)?\s+(\d[\d ]*)\s+\d{4}-", l)
        if m:
            files.append((m.group(1) + ("." + m.group(2) if m.group(2) else ""), int(m.group(3).replace(" ", ""))))
    return files


def main():
    build = sys.argv[1]
    total = n = 0
    for img, disk in DISKS:
        for name, size in listing(os.path.join(build, img)):
            if name == "RETROS.DSK":
                continue
            print(f"\\file{{{name}}} & {size:,} & {disk} & {D.get(name, 'The ' + name.split('.')[0] + ' command.')}\\\\")
            total += size
            n += 1
    print("\\midrule")
    print(f"{n} files & {total:,} & &\\\\")


if __name__ == "__main__":
    main()
