#!/bin/bash
#
# Builds a universal release binary and copies it to dist/speechkit.
#
# The x86_64 slice builds against the same on-disk SpeechKit checkout as the
# arm64 slice, so both architectures need the sibling ../SpeechKit directory.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Resolve the build directory before building, so the path query does not have
# to wait on the build's own lock on .build.
binary="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/speechkit"

echo "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64

if [[ ! -x "$binary" ]]; then
    echo "error: no binary at $binary" >&2
    exit 1
fi

mkdir -p dist
cp "$binary" dist/speechkit

echo
file dist/speechkit
lipo -info dist/speechkit
echo
echo "version: $(dist/speechkit --version)"
echo "wrote dist/speechkit"
