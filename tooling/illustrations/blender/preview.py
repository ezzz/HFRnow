#!/usr/bin/env python3
"""Contact sheet of renders on paper: python3 preview.py out/a.png out/b.png ... -> out/_preview.png"""
import sys, os, subprocess
files = sys.argv[1:]
here = os.path.dirname(os.path.abspath(__file__))
cells = "".join(f'<div style="background:#F8F5F0;padding:8px;text-align:center;font:12px sans-serif"><img src="file://{os.path.abspath(f)}" style="max-width:300px;max-height:300px"><br>{os.path.basename(f)}</div>' for f in files)
html = os.path.join(here, "out", "_preview.html")
open(html, "w").write(f'<html><body style="margin:0;background:#ddd;display:flex;flex-wrap:wrap;gap:6px;width:1300px">{cells}</body></html>')
subprocess.run(["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "--headless", "--disable-gpu", "--hide-scrollbars",
                "--window-size=1300,1000", "--screenshot=" + os.path.join(here, "out", "_preview.png"), "file://" + html], capture_output=True)
