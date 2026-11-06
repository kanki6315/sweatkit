#!/usr/bin/env python3
"""Disposable production-detail harness using unchanged real FIT recordings."""
from pathlib import Path
import shutil
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo / 'Scripts/RouteValidation/prepare.py'), str(out)], check=True)
for name in ('Harness.swift', 'UITests.swift'):
    shutil.copy2(Path(__file__).parent / name, out / name)
for name in ('walk', 'zwift-ride'):
    shutil.copy2(repo / 'Fixtures/fit' / (name + '.fit'), out / 'fit' / (name + '.fit'))
spec = out / 'project.yml'
spec.write_text(spec.read_text().replace('sweatkit.routesharness', 'sweatkit.playbackharness'))
