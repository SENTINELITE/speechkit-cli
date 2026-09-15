# speechkit

A macOS command-line tool that transcribes one or more audio files with any
[SpeechKit](../SpeechKit) file provider — ElevenLabs, Aqua, Cohere, Grok,
OpenAI, Meta, Gemini, or Apple's on-device Speech framework — and writes plain
text, JSON, SubRip, or WebVTT, with optional word-level timestamps and speaker
labels. It is a thin front end over the SpeechKit package: every provider
request goes through SpeechKit's detailed file-transcription calls, and the
responses are mapped into one neutral `TranscriptDocument` that the formatters
render. The package is a path dependency (`.package(path: "../SpeechKit")`), so
this checkout and the SpeechKit checkout must sit side by side in the same
parent directory and the tool always builds against whatever is on disk.

## Requirements

- macOS 15 or later to run the tool.
- macOS 26 or later for `--provider apple`. On macOS 15 the local speech
  analyzer does not exist and `--provider apple` exits with code 3.
- Xcode 26 or later (Swift 6.2 or later) to build.
- A sibling SpeechKit checkout at `../SpeechKit`.

## Build and install

```sh
swift build -c release
cp .build/release/speechkit ~/.local/bin/speechkit     # or /usr/local/bin
```

Or use the install script, which builds for the native architecture and copies
the binary into `$SPEECHKIT_INSTALL_DIR`, defaulting to `~/.local/bin`:

```sh
Scripts/install.sh
SPEECHKIT_INSTALL_DIR=/usr/local/bin Scripts/install.sh
```

For a universal (arm64 + x86_64) binary in `dist/speechkit`:

```sh
Scripts/build-release.sh
```

## Credentials

Every provider except Apple needs an API key. The tool looks in three places,
in this order, and stops at the first one that holds a non-empty value:

1. `--api-key <key>` on the command line.
2. The `SPEECHKIT_<PROVIDER>_API_KEY` environment variable.
3. The macOS login keychain, under service `com.sentinelite.speechkit-cli`
   with the provider name as the account.

If none of the three yields a key, the run exits with code 3 before any upload.

| Provider | Environment variable |
| --- | --- |
| `elevenlabs` | `SPEECHKIT_ELEVENLABS_API_KEY` |
| `aqua` | `SPEECHKIT_AQUA_API_KEY` |
| `cohere` | `SPEECHKIT_COHERE_API_KEY` |
| `grok` | `SPEECHKIT_GROK_API_KEY` |
| `openai` | `SPEECHKIT_OPENAI_API_KEY` |
| `meta` | `SPEECHKIT_META_API_KEY` |
| `gemini` | `SPEECHKIT_GEMINI_API_KEY` |
| `apple` | none; runs on device |

`SPEECHKIT_PROVIDER` supplies the default for `--provider`, so
`export SPEECHKIT_PROVIDER=openai` lets you drop the flag entirely.

The keychain is managed with `speechkit keys`:

```sh
speechkit keys set openai            # hidden prompt, no echo, nothing in shell history
speechkit keys set openai --from-stdin < key.txt
speechkit keys get openai            # sk-…4f2a
speechkit keys get openai --reveal
speechkit keys delete openai
speechkit keys list                  # default subcommand; also plain `speechkit keys`
```

`keys set` warns when the matching environment variable is also set, because
the variable wins over the keychain at transcription time. `apple` is rejected
by `set`, `get`, and `delete` with "apple needs no key".

Run `speechkit providers` to see, per provider, what it supports and whether a
credential was found on this machine right now (`env`, `keychain`, `none`, or
`not needed`). Add `--json` for machine-readable output.

## Quick start

```sh
# Word-timed WebVTT from OpenAI
speechkit transcribe interview.m4a --provider openai --language en --format vtt --words

# Diarized SubRip for a directory of files, three uploads at a time
speechkit transcribe *.wav --provider grok --format srt --diarize --output ./subs/ --jobs 3

# On-device transcription, JSON piped into jq
speechkit transcribe talk.mp3 --provider apple --language en-US --format json | jq .segments

# Discovery
speechkit providers
speechkit languages meta

# Batch: text and subtitles for every file in a folder, skipping ones already done
speechkit transcribe ./recordings/*.m4a \
  --provider gemini --language en-US \
  --format txt --format vtt \
  --output ./out/ --jobs 4 --verbose
```

Without `--output`, the transcript is printed to standard output. That works
for one input file and one format; anything more needs a directory. Pass
`--output` (or `-o`) with a directory to write `<input stem>.<format>` for each
input and format, or with a file path to name a single output. A path counts as
a directory when it already exists as one or ends with a slash. Existing files
are skipped with a warning unless `--overwrite` is passed, and the progress line
spells the skip out as `talk.txt (exists, skipped)`. Two inputs that share a
stem, such as `talk.wav` and `talk.mp3` in one run, would write over each other
in a directory, so the run is refused before any upload.

## `speechkit transcribe` flags

| Flag | Value | Default | Notes |
| --- | --- | --- | --- |
| `<files>` | one or more paths | — | Globs are expanded by the shell. A directory is rejected with a hint to use a glob. |
| `-p`, `--provider` | `elevenlabs`, `aqua`, `cohere`, `grok`, `openai`, `meta`, `gemini`, `apple` | `SPEECHKIT_PROVIDER` | Case-insensitive. Required when the variable is unset. |
| `-l`, `--language` | language code | provider default | Repeatable. Only OpenAI and Gemini use more than the first value. |
| `-m`, `--model` | provider model ID | provider default | Validated against the provider's model list. Ignored by Apple, which has none. |
| `--api-key` | string | — | Overrides the environment and keychain for this run. |
| `--endpoint` | URL | provider default | Override the file endpoint, for proxies. Ignored by Apple. |
| `--timeout` | seconds | 600 | Request timeout. Dropped by Aqua, Cohere, ElevenLabs, and Apple. |
| `--prompt` | string | — | OpenAI only. Dropped elsewhere. |
| `--keyword` | string | — | Repeatable vocabulary hint. OpenAI keywords, Meta keywords, Gemini custom vocabulary, Apple contextual strings. Dropped by Aqua, Cohere, ElevenLabs. |
| `--words` | flag | off | Request word-level timestamps. Usage error on Aqua, Cohere, and Meta. On OpenAI it selects `whisper-1`, the only model that returns them. |
| `--diarize` | flag | off | Speaker labels. Usage error on ElevenLabs, Aqua, Cohere, and Apple. On OpenAI it selects `gpt-4o-transcribe-diarize`. |
| `-f`, `--format` | `txt`, `json`, `srt`, `vtt` | `txt` | Repeatable: `-f srt -f vtt` writes both. |
| `-o`, `--output` | directory or file path | stdout | A directory (existing, or ending with `/`) takes any number of inputs and formats and is created if missing. A file path takes one input and one format. |
| `--overwrite` | flag | off | Without it, an existing output is skipped with a warning and the run still exits 0. |
| `--cues` | `segments`, `words` | `segments` | `words` writes one cue per word in SRT and VTT. |
| `--max-cue-duration` | seconds | `7.0` | Cue builder limit. Must be greater than zero. |
| `--max-cue-chars` | integer | `84` | Cue builder limit, two lines of 42. Must be greater than zero. |
| `-j`, `--jobs` | integer | `2` | Concurrent uploads. Values above 8 are capped with a warning. |
| `-v`, `--verbose` | flag | off | Per-file progress and timing to stderr. Per-provider notes print without it. |
| `-q`, `--quiet` | flag | off | Suppress warnings and progress. Cannot be combined with `--verbose`. |

`transcribe` is the default subcommand, so `speechkit talk.wav -p openai` works.

Everything that can be checked without an upload is checked first: the provider
supports the requested capabilities, the model and language are valid for the
provider and match the flags asked for, no two inputs would write to the same
path, the input exists and is readable, its extension is one the provider
accepts, and its size is under the provider's limit. Anything wrong there exits
with code 1 before a byte leaves the machine.

`--format srt` and `--format vtt` need timings, so with Grok, Gemini, OpenAI, or
ElevenLabs the upload asks for word timestamps whether or not `--words` was
passed. On OpenAI that means the run uses `whisper-1` unless `--model` says
otherwise, because OpenAI returns word timestamps from no other model.

## Providers

`speechkit providers` prints the live version of this table, including the
default model and where each credential was found.

| Provider | Words | Segments | Diarize | Language input | Max upload | Extensions |
| --- | --- | --- | --- | --- | --- | --- |
| `elevenlabs` | yes | yes | no | none (auto-detected) | 3 GB | any |
| `aqua` | no | no | no | fixed provider list | 25 MB | flac, m4a, mp3, mp4, mpeg, mpga, ogg, wav, webm |
| `cohere` | no | no | no | fixed provider list | 25 MB | flac, mp3, mpeg, mpga, ogg, wav |
| `grok` | yes | yes | yes | fixed provider list | 500 MB | aac, flac, m4a, mkv, mp3, mp4, ogg, opus, wav |
| `openai` | yes | yes | yes | ISO 639-1 | 25 MB | m4a, mp3, mp4, mpeg, mpga, wav, webm |
| `meta` | no | yes | yes | language names | 32 MB | wav |
| `gemini` | yes | yes | yes | BCP-47 | no byte limit (one hour per file) | aac, aif, aiff, flac, m4a, mp3, mpeg, mpga, ogg, opus, wav, webm |
| `apple` | yes | yes | no | `Locale` identifier | none | any |

Aqua and Cohere return text only, so `--format srt` or `--format vtt` with
either is a usage error rather than a wasted upload. Meta returns speaker
turns but no word timings, so `--words` is rejected there too.

Use `speechkit languages <provider>` for the accepted `--language` values.
Grok, Aqua, Cohere, and Meta print a fixed list; OpenAI and Gemini accept any
code, so they print a note instead; Apple prints the locales this machine's
transcriber actually supports. Region subtags such as `-US` are dropped before
matching against a fixed list, so `pt-BR` and `pt` resolve the same way.

### Flags dropped per provider

Flags that a provider cannot use are dropped rather than failing the run. The
note appears on stderr and in the `warnings` array of JSON output. With more
than one input file, the note is prefixed with the file it came from.

| Provider | Dropped |
| --- | --- |
| `elevenlabs` | `--language` (Scribe detects the language itself), `--timeout`, `--prompt`, `--keyword` |
| `aqua` | `--timeout`, `--prompt`, `--keyword` |
| `cohere` | `--timeout`, `--prompt`, `--keyword` |
| `grok` | `--prompt`, `--keyword` |
| `openai` | `--prompt` under `gpt-4o-transcribe-diarize`, which takes none |
| `meta` | `--prompt` |
| `gemini` | `--prompt`; `--keyword` is dropped when combined with `--diarize` or `--words`, which Gemini rejects |
| `apple` | `--model`, `--endpoint`, `--timeout`, `--prompt` |

Aqua, Cohere, and ElevenLabs also note that the transcript is a single untimed
segment, and Grok, Gemini, and ElevenLabs note when the provider returned no
word timings and the transcript collapsed to one untimed segment.

## Output formats

**txt** — the transcript text and a trailing newline. With `--diarize`, one
paragraph per speaker turn, prefixed `A: `, `B: `, and so on, separated by a
blank line.

**json** — the `TranscriptDocument`: provider, model, source file, text,
language, duration, segments, words, and warnings. Pretty-printed with sorted
keys.

**srt** — cues numbered from one, `00:00:01,520 --> 00:00:04,640` timings with a
comma before the milliseconds, a blank line between cues, UTF-8 with LF endings
and no byte order mark. With `--diarize`, cue text is prefixed `[A] `.

**vtt** — a `WEBVTT` header followed by a `NOTE` block recording provider,
model, and language, then cues with `.` before the milliseconds. With
`--diarize`, cue text is a `<v A>` voice span. With `--words`, cues carry inline
timing tags — `How <00:00:01.900>is <00:00:02.100>the` — which players use to
highlight words as they are spoken; the first word of a cue carries no tag
because the cue start already covers it.

Cues are built from segments by default. `--cues words` writes one cue per word
instead, for word-highlighting players; it needs word timings, so pass `--words`
with it. Lines are wrapped on word boundaries at the `--max-cue-chars` limit.

Subtitles are never guessed. If a transcript carries no timings, `srt` and `vtt`
fail for that file with a message naming the provider rather than inventing cue
times.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Every file succeeded. |
| 1 | Usage or configuration error found before any work: bad flag combination, unsupported capability, invalid model or language, missing or unreadable input, unsupported extension, oversized file, existing output, or no timing data for a subtitle format. |
| 2 | At least one file failed while others succeeded; the successful transcripts are still written and the failures are listed on stderr. |
| 3 | No credential for the provider, `--provider apple` on macOS 15, or a keychain failure. |

Transcripts go to standard output unless `--output` is passed. Progress,
warnings, and errors always go to standard error, so the tool stays pipeable.

## Shell completion

ArgumentParser generates the script:

```sh
mkdir -p ~/.zsh/completions
speechkit --generate-completion-script zsh > ~/.zsh/completions/_speechkit
```

Make sure `~/.zsh/completions` is on `fpath` before `compinit` runs in
`~/.zshrc`:

```sh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

`bash` and `fish` are also accepted in place of `zsh`.

## Tests

```sh
swift build -Xswiftc -warnings-as-errors
swift test
```

The unit suite is hermetic: no network, no keychain writes outside a temporary
in-memory store, and no media fixtures. Integration tests are disabled unless
credentials are present, so a plain `swift test` skips them rather than failing.

To enable them, export the key for each provider you want to exercise and run
the suite again. Each enabled test synthesises a short WAV with `say` and
`afconvert`, transcribes it, and checks the text:

```sh
export SPEECHKIT_OPENAI_API_KEY=sk-…
export SPEECHKIT_GROK_API_KEY=xai-…
swift test
```

The on-device Apple test needs no key, so it is gated on an explicit opt-in
instead:

```sh
SPEECHKIT_INTEGRATION=1 swift test
```

## Status

This is a local, unpublished tool. There is no GitHub remote, no CI, no
Homebrew tap, and no tagged release; the SpeechKit dependency is a path
dependency rather than a version, so both checkouts move together. Build it
from source with the steps above. Realtime microphone transcription, directory
watching, and a public release are follow-ups, not part of this version.
