#!/bin/sh
# Runs `swift test` in every package, or only in the packages named as arguments.
#   Scripts/test-packages.sh
#   Scripts/test-packages.sh SweatKitAnalysis SweatKitRouteMatching
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
packages=${*:-$(ls "$root/Packages")}
failed=""

for package in $packages; do
    echo "== $package"
    if ! (cd "$root/Packages/$package" && swift test --quiet); then
        failed="$failed $package"
    fi
done

if [ -n "$failed" ]; then
    echo "FAILED:$failed"
    exit 1
fi
echo "All packages passed."
