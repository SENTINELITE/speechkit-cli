class Speechkit < Formula
  desc "Transcribe audio files and export text, JSON, and subtitles"
  homepage "https://github.com/SENTINELITE/speechkit-cli"
  url "https://github.com/SENTINELITE/speechkit-cli/releases/download/1.0.2/speechkit-1.0.2-macos-arm64.tar.gz"
  version "1.0.2"
  sha256 "8ad5853f936cfef30076675ad891898457693179258cb6f03020947d46b309d2"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  def install
    bin.install "speechkit"
    doc.install Dir["share/doc/speechkit/*"]
  end

  test do
    assert_equal "1.0.2", shell_output("#{bin}/speechkit --version").strip
  end
end
