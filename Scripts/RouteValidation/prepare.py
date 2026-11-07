#!/usr/bin/env python3
"""Create a disposable UI harness; never inject fixture behavior into the production app."""
from pathlib import Path
import shutil
import sys

repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/routes-harness").resolve()
out.mkdir(parents=True, exist_ok=True)
shutil.copytree(repo / "App", out / "App", dirs_exist_ok=True)
for name in ("Harness.swift", "UITests.swift"):
    shutil.copy2(Path(__file__).parent / name, out / name)
fit = out / "fit"
fit.mkdir(exist_ok=True)
source = next((repo / "Fixtures").rglob("outdoor-ride.fit"))
shutil.copy2(source, fit / source.name)
model = out / "App/LibraryModel.swift"
model.write_text(model.read_text().replace("    func open() async {", "    func useFixtureLibrary(_ value: ActivityLibrary) async { library = value; await reload() }\n\n    func open() async {"))
spec = (repo / "project.yml").read_text()
spec = spec.replace("path: Packages/", f"path: {repo}/Packages/")
spec = spec.replace("      - App\n", "      - path: App\n        excludes: [SweatKitApp.swift, Info.plist]\n      - Harness.swift\n      - path: fit\n        buildPhase: resources\n")
spec = spec.replace("path: App/Info.plist", "path: HarnessInfo.plist")
spec = spec.replace("PRODUCT_BUNDLE_IDENTIFIER: com.arjunakankipati.sweatkit", "PRODUCT_BUNDLE_IDENTIFIER: com.arjunakankipati.sweatkit.routesharness")
spec = spec.replace("CODE_SIGN_ENTITLEMENTS: App/SweatKit.entitlements", 'CODE_SIGN_ENTITLEMENTS: ""')
spec = spec.replace("schemes:\n", """  RoutesUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests.swift]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: SweatKit
    dependencies:
      - target: SweatKit
schemes:
""")
spec = spec.replace("    run:\n", "    test:\n      targets: [RoutesUITests]\n    run:\n")
(out / "project.yml").write_text(spec)
print(out / "project.yml")
