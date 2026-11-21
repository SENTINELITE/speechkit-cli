class Speechkit < Formula
  desc "Transcribe audio files and export text, JSON, and subtitles"
  homepage "https://github.com/SENTINELITE/speechkit-cli"
  url "https://github.com/SENTINELITE/speechkit-cli/releases/download/1.0.0/speechkit-1.0.0-macos-arm64.tar.gz"
  version "1.0.0"
  sha256 "33a330d27b60700bd8fe6ac313ca025cc21f8ffe842f12fe685352ea380cf8f2"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  def install
    bin.install "speechkit"
    doc.install Dir["share/doc/speechkit/*"]
  end

  test do
    assert_equal "1.0.0", shell_output("#{bin}/speechkit --version").strip
  end
end
