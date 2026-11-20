# Release the CLI

Publish SpeechKit-Voz `1.1.0` first, then SpeechKit `3.0.0`. The demo
resolves the VOZ tag, and the standalone CLI resolves both tags. The CLI repository
and its GitHub Release assets must be readable by Homebrew users.

1. On an Apple Silicon Mac, run `swift test -Xswiftc -warnings-as-errors`
   in a checkout with no sibling-package override.
2. Run `Scripts/build-release.sh`. It writes
   `dist/speechkit-1.0.0-macos-arm64.tar.gz`, its SHA-256 file, and a matching
   `dist/speechkit.rb`. The archive contains the executable and license
   notices. VOZ downloads its model on first use.
3. Attach the archive and checksum to the GitHub Release for the bare
   `1.0.0` tag in `SENTINELITE/speechkit-cli`.
4. Place the generated formula in `Formula/speechkit.rb` in
   `SENTINELITE/homebrew-tap`. Verify the first install from the published URL.

```sh
brew trust --formula sentinellite/tap/speechkit
brew install sentinellite/tap/speechkit
brew test sentinellite/tap/speechkit
speechkit voz status
```

The 1.0 archive requires Apple Silicon and macOS 15 or later. The separately
named Apple Speech provider requires macOS 26 or later.
