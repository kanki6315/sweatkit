#!/usr/bin/env python3
"""Build a disposable long-feed regression harness using production app code."""
from pathlib import Path
import shutil
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo / 'Scripts/RouteValidation/prepare.py'), str(out)], check=True)
for name in ('Harness.swift', 'UITests.swift'):
    shutil.copy2(Path(__file__).parent / name, out / name)
