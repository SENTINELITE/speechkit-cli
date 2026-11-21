# Release the CLI

Publish SpeechKit-Voz `1.1.0` first, then SpeechKit `3.0.1`. The demo
resolves the VOZ tag, and the standalone CLI resolves both tags. The CLI repository
and its GitHub Release assets must be readable by Homebrew users.

Push `main` and a bare version tag such as `1.0.1`. The
[Apple Silicon release workflow](.github/workflows/release.yml) tests the
tagged source, builds the archive, and publishes it, its SHA-256 file, and
the matching `speechkit.rb` as GitHub Release assets. The workflow checks
that the binary reports the tag version before publishing.

For a local build on Apple Silicon, run `Scripts/build-release.sh`.
It writes the archive, checksum, and formula to `dist/`.

For Homebrew, download `speechkit.rb` from the published release so its
checksum matches the hosted archive. Update `Formula/speechkit.rb` in
this repository and push the formula to `main`. Verify the install with
the commands in the [Homebrew section of the README](README.md#install-with-homebrew)
followed by `brew test sentinellite/speechkit-cli/speechkit`.

The 1.0 archive requires Apple Silicon and macOS 15 or later. The separately
named Apple Speech provider requires macOS 26 or later.
