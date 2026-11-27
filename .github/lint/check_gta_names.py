#!/usr/bin/env python3
"""Fail when a GTA V name comes back into SPUR.

Reads the patterns in gta-names.txt and the allowed hits in gta-names-allow.txt (both next to this file),
then checks every text file git tracks. Prints each hit as path:line: text and exits 1 if there is any.

Run it from the repository root:  python3 .github/lint/check_gta_names.py
"""
import fnmatch
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SELF = os.path.relpath(HERE, os.getcwd()).replace(os.sep, '/') + '/'
LONG_LINE = 200  # a hit in a longer line (minified data, base64 fonts) is shown cut down


def read_rules(name):
    with open(os.path.join(HERE, name), encoding='utf-8') as f:
        return [line.rstrip('\n') for line in f if line.strip() and not line.lstrip().startswith('#')]


def load_patterns():
    return [(p, re.compile(p, re.IGNORECASE)) for p in read_rules('gta-names.txt')]


def load_allowed():
    """Each line is `path-glob<TAB>regex`: a hit is allowed when its file matches the glob and its line the regex."""
    allowed = []
    for line in read_rules('gta-names-allow.txt'):
        glob, _, rx = line.partition('\t')
        allowed.append((glob.strip(), re.compile(rx.strip() or '.', re.IGNORECASE)))
    return allowed


def tracked_text_files():
    # -I leaves out binary files (pictures, fonts); -l lists each file once.
    out = subprocess.run(['git', 'grep', '-I', '-l', '-e', ''], capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if not p.startswith(SELF)]


def main():
    patterns = load_patterns()
    allowed = load_allowed()
    hits = 0
    for path in tracked_text_files():
        try:
            with open(path, encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            for src, rx in patterns:
                m = rx.search(line)
                if not m:
                    continue
                if any(fnmatch.fnmatch(path, g) and a.search(line) for g, a in allowed):
                    continue
                text = line.strip()
                if len(text) > LONG_LINE:
                    s = max(m.start() - 60, 0)
                    text = '...' + line[s:m.end() + 60].strip() + '...'
                print(f'{path}:{n}: "{m.group(0)}" ({src})\n    {text}')
                hits += 1
                break
    if hits:
        print(f'\n{hits} GTA V name(s) found. SPUR follows Rockstar\'s mod guidelines, which keep one game\'s content'
              ' out of another: use an RDR2 or neutral name instead. If a hit is not GTA content, add it to'
              ' .github/lint/gta-names-allow.txt.')
        return 1
    print(f'No GTA V names found ({len(patterns)} patterns).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
