#!/bin/bash
#
# Builds a release binary for this machine's architecture and installs it into
# SPEECHKIT_INSTALL_DIR, which defaults to ~/.local/bin.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "error: speechkit 1.0 requires an Apple Silicon Mac and a native shell" >&2
    exit 1
fi

install_dir="${SPEECHKIT_INSTALL_DIR:-$HOME/.local/bin}"

binary="$(swift build -c release --show-bin-path)/speechkit"

echo "Building release binary..."
swift build -c release

if [[ ! -x "$binary" ]]; then
    echo "error: no binary at $binary" >&2
    exit 1
fi

mkdir -p "$install_dir"
cp "$binary" "$install_dir/speechkit"

echo "Installed $("$install_dir/speechkit" --version) to $install_dir/speechkit"

case ":${PATH}:" in
    *":${install_dir}:"*)
        ;;
    *)
        echo
        echo "$install_dir is not on your PATH. Add this to your shell profile:"
        echo "    export PATH=\"$install_dir:\$PATH\""
        ;;
esac
