#!/usr/bin/env python3
"""Build production snapshot/cache code in a disposable iOS test host."""
from pathlib import Path
import shutil
import sys
repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
for name in ('ThumbnailMapCache.swift', 'ThumbnailMapNetwork.swift', 'ThumbnailImageCache.swift'):
    shutil.copy2(repo / 'App' / name, out / name)
shutil.copy2(Path(__file__).parent / 'Tests.swift', out / 'Tests.swift')
(out / 'Harness.swift').write_text('''import SwiftUI
@main struct MapPreviewHarness: App {
    var body: some Scene { WindowGroup { Text("Map preview validation") } }
}
''')
(out / 'project.yml').write_text(f'''name: MapPreviewHarness
options:
  deploymentTarget:
    iOS: "26.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    CODE_SIGNING_ALLOWED: NO
packages:
  MapLibre:
    url: https://github.com/maplibre/maplibre-gl-native-distribution.git
    exactVersion: 7.0.0
  SweatKitModel:
    path: {repo / 'Packages/SweatKitModel'}
targets:
  MapPreviewHarness:
    type: application
    platform: iOS
    sources:
      - Harness.swift
      - ThumbnailMapCache.swift
      - ThumbnailMapNetwork.swift
      - ThumbnailImageCache.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sweatkit.map-preview-validation
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - package: MapLibre
      - package: SweatKitModel
  MapPreviewTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests.swift]
    dependencies:
      - target: MapPreviewHarness
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sweatkit.map-preview-tests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  MapPreviewHarness:
    build:
      targets:
        MapPreviewHarness: all
    test:
      targets: [MapPreviewTests]
''')
