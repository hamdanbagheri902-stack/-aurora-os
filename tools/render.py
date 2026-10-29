#!/usr/bin/env python3
"""render.py — fill @@TOKEN@@ placeholders in the copied build tree.

Usage: render.py BUILD_DIR KEY=value [KEY=value ...]
Replaces tokens inside every text file and in file/directory names.
An unknown token is an error, so typos are caught before a long build.
"""
import os
import re
import sys

TOKEN = re.compile(r"@@([A-Z_]+)@@")


def main() -> None:
    root = sys.argv[1]
    values = dict(arg.split("=", 1) for arg in sys.argv[2:])

    def fill(text: str, where: str) -> str:
        def repl(match):
            key = match.group(1)
            if key not in values:
                sys.exit(f"render.py: unknown token @@{key}@@ in {where}")
            return values[key]
        return TOKEN.sub(repl, text)

    changed = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ("cache", "chroot", "binary")]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                continue
            with open(path, "rb") as fh:
                data = fh.read()
            if b"\0" in data or b"@@" not in data:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            new = fill(text, path)
            if new != text:
                with open(path, "w", encoding="utf-8") as fh:  # keeps file mode
                    fh.write(new)
                changed += 1

    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        for name in dirnames + filenames:
            if "@@" in name:
                os.rename(os.path.join(dirpath, name),
                          os.path.join(dirpath, fill(name, os.path.join(dirpath, name))))

    print(f"render.py: filled tokens in {changed} file(s)")


if __name__ == "__main__":
    main()
