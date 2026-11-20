#!/bin/bash
# Build the Apple Silicon release archive and its matching Homebrew formula.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

export SPEECHKIT_INSTALL_DIR="$(mktemp -d)"
trap 'rm -rf "$SPEECHKIT_INSTALL_DIR"' EXIT
Scripts/install.sh
binary="$SPEECHKIT_INSTALL_DIR/speechkit"
version="$("$binary" --version)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: unexpected CLI version" >&2
    exit 1
fi

docs="$SPEECHKIT_INSTALL_DIR/share/doc/speechkit"
mkdir -p "$docs"
cp LICENSE NOTICE.md "$docs/"
cp .build/checkouts/swift-argument-parser/LICENSE.txt "$docs/swift-argument-parser-LICENSE.txt"
cp .build/checkouts/swift-numerics/LICENSE.txt "$docs/swift-numerics-LICENSE.txt"
cp .build/checkouts/desert-ant-core/LICENSE.md "$docs/desert-ant-LICENSE.md"
cp -R .build/checkouts/desert-ant-core/LICENSES "$docs/desert-ant-LICENSES"
cp .build/checkouts/desert-ant-core/THIRD_PARTY_NOTICES.md "$docs/desert-ant-THIRD_PARTY_NOTICES.md"

mkdir -p dist
archive="speechkit-${version}-macos-arm64.tar.gz"
COPYFILE_DISABLE=1 tar -czf "dist/$archive" -C "$SPEECHKIT_INSTALL_DIR" speechkit share
sha="$(shasum -a 256 "dist/$archive" | cut -d' ' -f1)"
printf '%s  %s\n' "$sha" "$archive" > "dist/$archive.sha256"

cat > dist/speechkit.rb <<FORMULA
class Speechkit < Formula
  desc "Transcribe audio files and export text, JSON, and subtitles"
  homepage "https://github.com/SENTINELITE/speechkit-cli"
  url "https://github.com/SENTINELITE/speechkit-cli/releases/download/$version/$archive"
  version "$version"
  sha256 "$sha"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  def install
    bin.install "speechkit"
    doc.install Dir["share/doc/speechkit/*"]
  end

  test do
    assert_equal "$version", shell_output("#{bin}/speechkit --version").strip
  end
end
FORMULA

echo "Release archive: dist/$archive"
echo "SHA-256: dist/$archive.sha256"
echo "Homebrew formula: dist/speechkit.rb"
