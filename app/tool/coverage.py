"""Line coverage of the app from coverage/lcov.info (flutter test --coverage).

Excluded: generated localizations and the code that only runs on a device or in the
browser (platform start, Firebase push, GPS of the phone, WebSocket factories, sharing and download of files,
links opened in other apps). Fails
below the minimum.

    python tool/coverage.py [minimum] [--files]
"""
import os
import re
import sys

EXCLUDED = [
    r"^lib/l10n/",
    r"^lib/main\.dart$",
    r"^lib/core/push\.dart$",
    r"^lib/core/phone_service\.dart$",
    r"^lib/core/ws_connect(_io|_web)?\.dart$",
    r"^lib/core/save_file(_io|_web)?\.dart$",
    r"^lib/core/open_url\.dart$",
]

here = os.path.dirname(os.path.abspath(__file__))
minimum = float(next((a for a in sys.argv[1:] if not a.startswith("--")), "98"))
files = {}
current = None
with open(os.path.join(here, "..", "coverage", "lcov.info"), encoding="utf-8") as lcov:
    for line in lcov:
        line = line.strip()
        if line.startswith("SF:"):
            current = line[3:].replace("\\", "/")
            current = current[current.index("lib/"):]
            files.setdefault(current, {})
        elif line.startswith("DA:") and current:
            number, hits = line[3:].split(",")[:2]
            files[current][int(number)] = files[current].get(int(number), 0) + int(hits)

total = covered = 0
rows = []
for name, lines in sorted(files.items()):
    if any(re.search(pattern, name) for pattern in EXCLUDED):
        continue
    hit = sum(1 for count in lines.values() if count > 0)
    total += len(lines)
    covered += hit
    missing = [n for n, count in sorted(lines.items()) if count == 0]
    rows.append((name, hit, len(lines), missing))

if "--files" in sys.argv:
    for name, hit, count, missing in rows:
        if missing:
            print(f"{100 * hit / count:6.1f}%  {name}  missing: {','.join(map(str, missing))}")

percent = 100 * covered / total if total else 0
print(f"Lines: {covered}/{total} = {percent:.2f}% (minimum {minimum}%)")
sys.exit(0 if percent >= minimum else 1)
