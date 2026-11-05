#!/usr/bin/env python3
"""Build a disposable integration harness around the production RootView.
The route fixture derivative and library injection exist only in this harness.
"""
from pathlib import Path
import shutil
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo / "Scripts/RouteValidation/prepare.py"), str(out)], check=True)
for name in ("Harness.swift", "UITests.swift"):
    shutil.copy2(Path(__file__).parent / name, out / name)
for name in ("walk", "zwift-ride"):
    shutil.copy2(repo / "Fixtures/fit" / (name + ".fit"), out / "fit" / (name + ".fit"))
model = out / "App/LibraryModel.swift"
model.write_text(model.read_text().replace("library = value; await reload()", "library = value; cloud = CloudConnection(library: value, root: value.store.root); await reload()"))
