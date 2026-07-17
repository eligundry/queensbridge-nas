#!/usr/bin/env python3
"""Rewrite Jellyfin container media paths -> laptop SMB mount paths.

  /data/tv     -> /Users/eligundry/nas-media/TV
  /data/movies -> /Users/eligundry/nas-media/Movies
  /data/music  -> /Users/eligundry/nas-media/Music

Data-driven: scans every column of every table for the prefixes and rewrites
them in place. Pass --apply to write; default is a dry-run report.
"""
import sqlite3, sys

DB = sys.argv[1]
APPLY = "--apply" in sys.argv

MAP = [
    # container config/data dir -> laptop data dir (metadata images, virtual roots)
    ("/config/data", "/Users/eligundry/.local/share/jellyfin/data"),
    # media library folders -> laptop SMB mount
    ("/data/tv",     "/Users/eligundry/nas-media/TV"),
    ("/data/movies", "/Users/eligundry/nas-media/Movies"),
    ("/data/music",  "/Users/eligundry/nas-media/Music"),
]

con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
cur = con.cursor()

tables = [r[0] for r in cur.execute(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]

total = 0
plan = []
for t in tables:
    cols = [r["name"] for r in cur.execute(f'PRAGMA table_info("{t}")')]
    for c in cols:
        # count rows containing any of the prefixes
        conds = " OR ".join([f'"{c}" LIKE ?' for _ in MAP])
        params = [f"%{old}%" for old, _ in MAP]
        try:
            n = cur.execute(
                f'SELECT COUNT(*) FROM "{t}" WHERE {conds}', params).fetchone()[0]
        except sqlite3.OperationalError:
            continue  # non-text / unindexable column
        if n:
            plan.append((t, c, n))
            total += n

print(f"{'APPLY' if APPLY else 'DRY-RUN'} on {DB}")
print(f"{'table':40} {'column':28} rows")
print("-" * 76)
for t, c, n in plan:
    print(f"{t:40} {c:28} {n}")
print("-" * 76)
print(f"total cells to rewrite: {total}")

if APPLY and plan:
    for t, c, _ in plan:
        expr = f'"{c}"'
        for old, new in MAP:
            expr = f"REPLACE({expr}, '{old}', '{new}')"
        conds = " OR ".join([f'"{c}" LIKE ?' for _ in MAP])
        params = [f"%{old}%" for old, _ in MAP]
        cur.execute(f'UPDATE "{t}" SET "{c}" = {expr} WHERE {conds}', params)
    con.commit()
    print("committed ✅")
con.close()
