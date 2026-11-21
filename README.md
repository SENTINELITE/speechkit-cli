# speechkit

A macOS command-line tool for transcribing audio files with
[SpeechKit](https://github.com/SENTINELITE/SpeechKit). Export plain text, JSON,
SubRip, or WebVTT, with optional word timings and speaker labels. Run
`speechkit bench` to compare providers on the same recordings.

## Requirements

- Apple Silicon Mac with macOS 15 or later.
- macOS 26 or later to use Apple's on-device Speech framework.
- About 337 MB of disk for the VOZ v0.5.0 model, downloaded on demand.
- Xcode 26 or later (Swift 6.2 or later) for source builds.

## Install with Homebrew

Tap this repository by its GitHub URL, then install `speechkit`:

```sh
brew tap sentinellite/speechkit-cli https://github.com/SENTINELITE/speechkit-cli.git
brew trust --formula sentinellite/speechkit-cli/speechkit
brew install sentinellite/speechkit-cli/speechkit
speechkit --version
```

Updates are available through `brew upgrade sentinellite/speechkit-cli/speechkit`.

## Install from GitHub

Download the archive ending in `-macos-arm64.tar.gz` and its checksum from
[GitHub Releases](https://github.com/SENTINELITE/speechkit-cli/releases/latest).
In the download directory, verify, unpack, and install the executable:

```sh
shasum -a 256 -c speechkit-1.0.1-macos-arm64.tar.gz.sha256
tar -xzf speechkit-1.0.1-macos-arm64.tar.gz
mkdir -p ~/.local/bin
install -m 0755 speechkit ~/.local/bin/speechkit
~/.local/bin/speechkit --version
```

Use the filenames for the version you downloaded. Add `~/.local/bin` to
`PATH` to run `speechkit` by name. VOZ downloads its model on first use.

## Build from source

Clone this repository and run:

```sh
Scripts/install.sh
```

The default install path is `~/.local/bin/speechkit`. Set
`SPEECHKIT_INSTALL_DIR` to choose another path. Source builds resolve
SpeechKit 3.x and SpeechKit-Voz 1.x from GitHub. For development across
sibling checkouts, set `SPEECHKIT_VOZ_USE_LOCAL_SPEECHKIT=1` for SwiftPM
commands and build scripts.

See [release packaging](RELEASING.md) for the Homebrew tap and archive.

## Credentials

Cloud providers need an API key. Apple and VOZ run on device. The tool looks in three places,
in this order, and stops at the first one that holds a non-empty value:

1. `--api-key <key>` on the command line.
2. The `SPEECHKIT_<PROVIDER>_API_KEY` environment variable, with any hyphen
   in the provider name written as an underscore. Fish Audio also reads
   `FISH_API_KEY` when its `SPEECHKIT_` variable is unset.
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
| `fish-audio` | `SPEECHKIT_FISH_AUDIO_API_KEY`, then `FISH_API_KEY` |
| `apple` | none; runs on device |
| `voz` | none; runs on device |

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
the variable wins over the keychain at transcription time. `apple` and `voz`
are rejected by `set`, `get`, and `delete` with "apple needs no key" and
"voz needs no key".

New and replaced Keychain entries use `WhenUnlockedThisDeviceOnly` and are
explicitly non-synchronizable. Save updates an existing entry without deleting
it first, and every save and delete status is checked. Re-save older entries
with `keys set` to apply the unlocked-only policy.

Provider failures print SpeechKit 3.0's safe failure categories and HTTP status
codes, not raw response bodies, transport descriptions, or credentials. The same
messages go to benchmark reports, live key checks, and usage history. Unknown
failures use a generic connection failure rather than echoing their details.

Run `speechkit providers` to see, per provider, what it supports and whether a
credential was found on this machine right now (`env`, `keychain`, `none`, or
`not needed`). Add `--json` for machine-readable output.

### Checking keys in bulk

`speechkit keys check` reports where every provider's key would come from,
without contacting anyone:

```console
$ speechkit keys check
PROVIDER    SOURCE      ENV VAR                       KEY
elevenlabs  keychain    SPEECHKIT_ELEVENLABS_API_KEY  ••••4f2a
openai      env         SPEECHKIT_OPENAI_API_KEY      ••••91ab
aqua        none        SPEECHKIT_AQUA_API_KEY        -
apple       not needed  -                             -
voz         not needed  -                             -
```

Name providers to narrow it (`speechkit keys check openai grok`); no argument,
or `all`, checks every provider. Keys are always redacted to their last four
characters.

`--live` verifies each key by transcribing a short clip generated on the fly
with `say` and `afconvert`, adding `STATUS` (`ok`, `failed`, `skipped`), `TIME`,
and `DETAIL` columns. Network providers are checked four at a time; Apple and
VOZ run on device. A VOZ model that is not downloaded is reported `skipped`
rather than fetched, so a check never triggers the model download.

```console
$ speechkit keys check openai --live
PROVIDER  SOURCE  ENV VAR                   KEY       STATUS  TIME  DETAIL
openai    env     SPEECHKIT_OPENAI_API_KEY  ••••1234  failed  0.3   openAI upload failed: { "error": { "message": "Incorrect ...
```

`--json` emits the same rows as an array of objects, with the untruncated
`detail`. Exit codes: `0` when every requested provider is usable, `2` when a
live check failed, and `3` when any requested provider has no key. Run it
before a `bench` to know which providers will take part.

Each provider that is actually probed is recorded in the [usage
history](#usage-history); `--no-history` turns that off.

## Quick start

```sh
# Word-timed WebVTT from OpenAI
speechkit transcribe interview.m4a --provider openai --language en --format vtt --words

# Diarized SubRip for a directory of files, three uploads at a time
speechkit transcribe *.wav --provider grok --format srt --diarize --output ./subs/ --jobs 3

# On-device VOZ: one timestamped sentence per line, plus JSON with word timings
speechkit transcribe talk.m4a --provider voz --format txt --format json --output ./out/

# On-device transcription, JSON piped into jq
speechkit transcribe talk.mp3 --provider apple --language en-US --format json | jq .segments

# Compare three providers over a folder, scored against reference transcripts
speechkit bench ./recordings/ -p voz -p apple -p openai -o ./bench/ --reference-dir ./refs/

# Discovery
speechkit providers
speechkit languages meta

# What has this machine transcribed?
speechkit stats --by provider --since 30d

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

## Interactive mode

Run `speechkit` with no arguments on a terminal and it walks through the run
with arrow keys instead of flags. `speechkit interactive`, or its alias
`speechkit ui`, forces it; off a terminal that prints an error naming the
headless form instead. Nothing else changes: a bare `speechkit` in a script,
with standard input redirected, prints the usage error it always has, and
`speechkit talk.wav -p voz` still transcribes, because the routing happens only
when there are no arguments at all and both standard input and standard error
are terminals.

The prompts scroll like `npm init` rather than taking over the screen. Each one
clears itself when answered and leaves a single line behind, so the scrollback
reads like a filled-in form:

```
? What do you want to do?  Transcribe files
? Provider  voz
? Files  talk.wav
? Formats  txt
? Word timestamps?  No
? Output  next to the inputs

  speechkit transcribe talk.wav -p voz -f txt -o ./

? Run it?  Yes
[1/1] talk.wav -> talk.txt (voz, 0.1 s)
```

The flow is: what to do, then for a transcription the provider, the files, the
formats, word timestamps, speaker labels, and where the output goes. The
provider list carries its own status — `on device, ready`, `on device, model
not downloaded`, `key: keychain`, `key: env`, or `no key` — so there is no
guessing about what will work. Questions a provider cannot answer are not
asked: VOZ is never asked about speaker labels, because it has none. The file
step lists the audio files in the current directory when there are any, with a
row at the end that opens a path prompt where tab completes against the file
system and a glob such as `*.wav` is expanded here, since there is no shell to
expand it. `stdout` is offered only for one file in one format, which is the
same rule `transcribe` enforces.

The last thing before anything runs is the command itself, printed exactly as
it could be pasted into a script, with any path that needs it quoted.
`Copy command` puts it on the clipboard with `pbcopy`, and `Back` returns to
the previous question. Choosing `Yes` parses that command line and runs it, so
validation, the progress rows, the output files, the usage history, and the
exit codes are the headless ones; interactive mode has no run path of its own,
and history records the run under `transcribe` or `bench` exactly as if it had
been typed.

The first three questions are prefilled from the [usage
history](#usage-history): the provider, the formats, and the output directory
of the most recent successful `transcribe`. With no history at all, the offer
is VOZ when its model is downloaded, Apple on macOS 26, and otherwise the first
provider that has a key.

Choosing a provider with no key drops into the key prompt for it — the same
keychain write `speechkit keys set` performs, with the key hidden as it is
typed — and comes back. Choosing VOZ when the model is not downloaded asks
before fetching it. The other two entries from the first question set a key for
any provider, and download the VOZ model with the progress bar `voz prepare`
draws.

`Benchmark providers` collects the providers (with `all`), the files, the
formats, an optional reference transcript directory, a repeat count, and the
output directory, and then shows and runs the `speechkit bench` command those
answers make.

Escape steps back one question, and escape at the first question leaves.
`Ctrl-C` and `Ctrl-D` restore the terminal and exit 130. Prompts are drawn on
standard error and never on standard output, so a transcript sent to `stdout`
from a session started this way pipes as cleanly as any other.

## `speechkit transcribe` flags

| Flag | Value | Default | Notes |
| --- | --- | --- | --- |
| `<files>` | one or more paths | — | Globs are expanded by the shell. A directory is rejected with a hint to use a glob. |
| `-p`, `--provider` | `elevenlabs`, `aqua`, `cohere`, `grok`, `openai`, `meta`, `gemini`, `fish-audio`, `apple`, `voz` | `SPEECHKIT_PROVIDER` | Case-insensitive. `fish` is accepted for `fish-audio`. Required when the variable is unset. |
| `-l`, `--language` | language code | provider default | Repeatable. Only OpenAI and Gemini use more than the first value. |
| `-m`, `--model` | provider model ID | provider default | Validated against the provider's model list. Ignored by Apple and VOZ, which have none. |
| `--api-key` | string | — | Overrides the environment and keychain for this run. |
| `--endpoint` | URL | provider default | Override the file endpoint. HTTPS required, except HTTP on loopback. Ignored by Apple and VOZ. |
| `--files-endpoint` | URL | provider default | Gemini Files API route. Required with a custom Gemini `--endpoint`, on the same origin. Other providers reject it. |
| `--timeout` | seconds | 600 (900 for ElevenLabs and Fish Audio) | Request timeout. Dropped by Aqua, Cohere, Apple, and VOZ. |
| `--prompt` | string | — | OpenAI only. Dropped elsewhere. |
| `--keyword` | string | — | Repeatable vocabulary hint. ElevenLabs keyterms, OpenAI keywords, Meta keywords, Gemini custom vocabulary, Apple contextual strings. Dropped by Aqua, Cohere, Grok, and Fish Audio. |
| `--words` | flag | off | Request word-level timestamps. Usage error on Aqua, Cohere, and Meta. On OpenAI it selects `whisper-1`, which OpenAI retires on February 26, 2027 but is still the only model that returns them. |
| `--diarize` | flag | off | Speaker labels. Usage error on Aqua, Cohere, Apple, and VOZ. On OpenAI it selects `gpt-4o-transcribe-diarize`, which OpenAI retires on February 26, 2027; the run prints a note. |
| `--speakers` | integer | model maximum | ElevenLabs only: maximum number of speakers, 1-32. Requires `--diarize`. |
| `--numbers` | `digits`, `words` | model choice | ElevenLabs `scribe_v3` only: how numbers are written. |
| `--secondary-language` | language code | — | ElevenLabs `scribe_v3` only: another language expected in the audio. Repeatable. |
| `--tag-audio-events` | flag | off | ElevenLabs only: tag sounds such as laughter. They come back as words with no timestamps. |
| `--no-verbatim` | flag | off | ElevenLabs only: remove filler words and false starts. |
| `-f`, `--format` | `txt`, `json`, `srt`, `vtt` | `txt` | Repeatable: `-f srt -f vtt` writes both. |
| `-o`, `--output` | directory or file path | stdout | A directory (existing, or ending with `/`) takes any number of inputs and formats and is created if missing. A file path takes one input and one format. |
| `--no-timestamps` | flag | off | Write `txt` as prose instead of one timestamped sentence per line. |
| `--overwrite` | flag | off | Without it, an existing output is skipped with a warning and the run still exits 0. |
| `--cues` | `segments`, `sentences`, `words` | `sentences` for VOZ and Fish Audio, `segments` otherwise | `sentences` rebuilds the segments, in every format, as one per sentence from the word timings. `words` writes one cue per word in SRT and VTT. |
| `--max-cue-duration` | seconds | `7.0` | Cue builder limit. Must be greater than zero. |
| `--max-cue-chars` | integer | `84` | Cue builder limit, two lines of 42. Must be greater than zero. |
| `--no-download` | flag | off | Fail with exit 3 instead of downloading a missing on-device model. VOZ only. |
| `-j`, `--jobs` | integer | `2` | Concurrent uploads. Values above 8 are capped with a warning. |
| `--no-history` | flag | off | Do not record this run in the local usage history. `SPEECHKIT_NO_HISTORY` does the same for every run. |
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

### Custom endpoints

Custom endpoints cannot contain user info, fragments, or credential query
parameters. SpeechKit 3.0 refuses redirects, including same-origin redirects;
pass the final destination URL instead. File transcription uses HTTP endpoints,
not WebSocket endpoints.

Gemini custom routes must be complete. `--endpoint` must end in `/interactions`,
and `--files-endpoint` must end in `/files`, with the same scheme, host, and port:

```sh
speechkit talk.wav -p gemini \
  --endpoint https://proxy.example.com/v1beta/interactions \
  --files-endpoint https://proxy.example.com/upload/v1beta/files
```

Both routes are explicit so uploads and follow-up requests cannot silently fall
back to Google. These overrides still use your API key; they do not enable
Relay or bearer-token authentication.

## Benchmarking providers

`speechkit bench` runs the same audio through several providers and writes one
table comparing them on speed, output size, and accuracy. It is for the question
"which of these should I use for this kind of recording", so the transcripts are
written side by side for reading and the numbers are written three ways for
sorting.

```sh
speechkit bench ./recordings/ -p voz -p apple -p grok -o ./bench/
speechkit bench a.wav b.m4a -p openai -p gemini --words -o ./bench/ --repeat 3 --reference-dir ./refs/
```

Positional arguments are files or directories. A directory contributes its
top-level files whose extension is one of `wav`, `mp3`, `m4a`, `aac`, `flac`,
`ogg`, `opus`, `mp4`, `webm`, `aiff`, `aif`, or `caf`, sorted by name; `--recursive`
walks subdirectories too. Hidden files are skipped. A file named outright is
taken whatever it is called.

`-p`/`--provider` is repeatable and at least one is required. `all` expands to
every provider that has a credential on this machine or needs none, which is
exactly what the credential column of `speechkit providers` shows. A provider
named explicitly with no credential is a warning and a skip, not the end of the
run: one missing key should not cost you the other five columns. The run exits
with code 3 only when no provider could run at all.

Providers run one after another, and within a provider the files run one at a
time by default, because two uploads in flight make each other's timings
meaningless. `--jobs` raises that if you only care about throughput. VOZ loads
its Core ML model once for the whole provider pass; that load is reported as
`setup_seconds` in the summary and is deliberately left out of the per-file
timings.

### What is timed

The clock starts immediately before the provider call and stops when it
returns, using `ContinuousClock`. Finding the files, checking them against the
provider's limits, rendering text or subtitles, writing files, probing the audio
duration, and scoring the word error rate all happen outside it. `wall_seconds`
is therefore the provider's number and nothing else — for a cloud provider it
includes the upload and the queue, because you pay for those too.

With `--repeat N` each file is transcribed N times per provider;
`wall_seconds` is the mean and `wall_min_seconds` the fastest. Only the last
run's transcript is kept.

### Output layout

Everything goes in the `-o` directory:

```
bench/
  talk.apple.txt        # <stem>.<provider>.<format>, one per --format
  talk.voz.txt
  talk.voz.srt
  summary.csv
  summary.md
  summary.json
```

`--format` defaults to `txt` and is repeatable; `--json-transcripts` adds the
full JSON document whatever `--format` says. An existing transcript file is
skipped with a warning unless `--overwrite` is passed. The three summary files
are always rewritten.

### Columns

One row per file per provider, sorted by file and then provider. A cell is
blank when nothing supplied it, so a failed run never contributes a zero to a
column you might average.

| Column | Meaning |
| --- | --- |
| `file` | The input file name. |
| `provider` | The provider that produced the row. |
| `model` | The model the provider reported. Blank for Apple, which has none. |
| `audio_seconds` | The audio duration, from the transcript when the provider reports one, otherwise probed with AVFoundation. |
| `wall_seconds` | Mean wall time of the provider call, over `--repeat`. |
| `wall_min_seconds` | The fastest of those repeats. |
| `realtime_factor` | `audio_seconds / wall_seconds`. `20x` means twenty seconds of audio a second. |
| `processing_seconds` | Compute time the provider reported, not wall time. VOZ reports it; the cloud providers do not. |
| `billed_seconds` | Billable audio seconds the provider counted. OpenAI and Aqua report it. |
| `total_tokens` | Tokens the provider counted, for the token-billed models. Blank elsewhere. |
| `chars` | Characters of transcript text. |
| `words` | Words of transcript text, counted after the same normalisation the word error rate uses. |
| `est_tokens` | An estimate, `ceil(chars / 4)`, for comparing providers none of which reports tokens. It is a rule of thumb, not a tokenizer. |
| `bytes` | Bytes of the plain-text transcript. |
| `segments` | Segments in the transcript. |
| `has_word_timings` | Whether the transcript carries word-level timings. |
| `wer` | Word error rate against the reference, to three decimals. Blank without one. |
| `status` | `ok`, or the error. Cut short in the CSV and the Markdown; whole in `summary.json`. |

`summary.md` carries a second, smaller table aggregating each provider: files,
failures, total audio seconds, total wall seconds, the overall realtime factor,
the mean word error rate where there was one, and `setup_seconds`. That table is
also printed to standard output when the run finishes, unless `--quiet`.
Progress stays on standard error, one line per file:

```
[voz 3/12] talk.wav 0.4 s (12.1x)
```

### Word error rate

Pass `--reference-dir` and the run looks for `<stem>.txt` in it. Without the
flag, a `<stem>.reference.txt` sitting beside the input counts instead, so a
folder can carry its own answers.

Both sides are normalised the same way: lowercased, every character that is not
a letter, a digit, or an apostrophe treated as a separator, apostrophes kept
only inside a word, and whitespace collapsed. Nothing else is expanded — "25"
and "twenty five" stay different, and so do "Dr" and "doctor". The score is the
word-level Levenshtein distance divided by the number of words in the reference,
reported to three decimals. It can exceed one, when a provider says more than
the reference does. An empty reference is reported as a blank cell rather than a
division by zero.

Word error rate is a coarse instrument, and the point of writing the transcripts
side by side is that you can read them. A provider that writes "seashore" where
the reference says "sea shore" scores two errors for something no listener would
call a mistake.

## `speechkit bench` flags

The flag set is small on purpose. `--model`, `--api-key`, `--endpoint`, `--files-endpoint`,
`--timeout`, `--prompt`, and the `--max-cue-*` limits are not accepted: a value
that can only suit one of the providers being compared makes two columns
incomparable, and credentials that belong to one provider cannot be passed on a
command line comparing several. Keys come from the environment and the keychain
only.

| Flag | Value | Default | Notes |
| --- | --- | --- | --- |
| `<inputs>` | files or directories | — | A directory contributes its audio files. |
| `-p`, `--provider` | a provider name, or `all` | — | Repeatable. Required. |
| `-o`, `--output` | directory | — | Required. Created if missing. |
| `-l`, `--language` | language code | provider default | Repeatable. Passed to every provider. |
| `--words` | flag | off | Request word-level timestamps from every provider. |
| `--diarize` | flag | off | Request speaker labels from every provider. |
| `-f`, `--format` | `txt`, `json`, `srt`, `vtt` | `txt` | Repeatable. Written per file and provider. |
| `--json-transcripts` | flag | off | Also write the JSON document for every file. |
| `--reference-dir` | directory | — | Holds `<stem>.txt` reference transcripts for the word error rate. |
| `--recursive` | flag | off | Include audio files in subdirectories. |
| `--repeat` | integer | `1` | Transcribe each file this many times per provider. |
| `-j`, `--jobs` | integer | `1` | Files in flight per provider, capped at 8. One, for fair timing. |
| `--no-download` | flag | off | Fail instead of downloading a missing on-device model. |
| `--overwrite` | flag | off | Replace existing transcript files. Summaries are always rewritten. |
| `--no-history` | flag | off | Do not record these runs in the local usage history. |
| `-v`, `--verbose` | flag | off | Per-file progress to stderr whether or not it is a terminal. |
| `-q`, `--quiet` | flag | off | Suppress warnings, progress, and the aggregate table. |

A file the provider rejects before the upload — missing, unreadable, too large,
an extension it does not accept — is a failed row rather than a failed run,
because Aqua's 25 MB limit should not abort the Gemini pass over the same
folder. So is a `--model`-less provider that cannot serve `--words` or
`--diarize`. The run exits with code 2 when any row failed.

## Usage history

Every `transcribe` run, every `bench` row, and every provider `keys check
--live` actually probes is appended to
`~/Library/Application Support/speechkit/history.jsonl`, one JSON object per
line, so `speechkit stats` can answer how much audio went through which
provider and how fast.

Recorded: the timestamp, the CLI version, the command, the provider and model,
the input file name and path, its size, the audio duration, the wall time of
the run, the realtime factor, the word and character counts, the formats
written, whether `--words` and `--diarize` were asked for, the `--repeat` count
for `bench`, and either `ok` or a short error class (`credential`, `provider`,
`validation`, `write`) with the first line of the failure.

Never recorded: transcript text, API keys, reference transcripts, and word
error rates. The history file is not a second copy of anyone's audio content.
The directory is created `0700` and the file `0600`.

Pass `--no-history` to `transcribe`, `bench`, or `keys check` to record
nothing for that run, or set `SPEECHKIT_NO_HISTORY` to anything non-empty to
record nothing at all. When recording is off, nothing is written and nothing is
created. `SPEECHKIT_HISTORY_DIR` moves the file somewhere else.

```console
$ speechkit stats
Since 2026-09-15 (1 day), 6 runs, 3 files, 0 failures
Audio transcribed     23.2 s
Wall time             1.3 s
Realtime factor       17.4x
Words                 60
Most used commands    transcribe 4, keys check 2
Most used providers   apple 3, voz 3
Fastest provider      apple 18.4x   Slowest  voz 16.5x
```

Realtime factors are always total audio divided by total wall time, never an
average of the per-run factors: averaging would weigh a two-second clip the
same as a two-hour recording.

`--since` takes `24h`, `7d`, `30d`, or a date such as `2026-09-01`. `--by`
groups the rows:

```console
$ speechkit stats --by provider
PROVIDER  RUNS  FILES  AUDIO   WALL   REALTIME  WORDS  FAILURES
apple     3     3      11.5 s  0.6 s  18.4x     30     0
voz       3     3      11.7 s  0.7 s  16.5x     30     0

$ speechkit stats --by command
COMMAND     RUNS  FILES  WALL   FAILURES
transcribe  4     2      0.6 s  0
keys check  2     1      0.7 s  0

$ speechkit stats --by day --since 30d
DAY         RUNS  FILES  AUDIO   WALL   REALTIME  WORDS
2026-09-15  6     3      23.2 s  1.3 s  17.4x     60
```

`speechkit history` lists the runs themselves, newest first, 20 by default:

```console
$ speechkit history --limit 3
WHEN              COMMAND     PROVIDER  FILE       AUDIO  WALL   REALTIME  WORDS  STATUS
2026-09-15 15:17  keys check  voz       probe.wav  1.5 s  0.5 s  2.9x      0      ok
2026-09-15 15:17  keys check  apple     probe.wav  1.5 s  0.2 s  7.7x      0      ok
2026-09-15 15:17  transcribe  voz       b.wav      5.1 s  0.1 s  61.5x     15     ok
```

`--provider`, `--failed`, and `--since` narrow it, and `--json` emits the
records themselves. `speechkit stats --json` emits the totals and every
grouping as one object.

`speechkit history clear` deletes the file after a confirmation; `--yes` skips
it, and off a terminal `--yes` is required. `stats` on an empty or missing
history prints `No history yet. Runs are recorded after the first
transcription.` and exits 0. A line that cannot be read is skipped with one
warning rather than failing the command.

## Providers

`speechkit providers` prints the live version of this table, including the
default model and where each credential was found.

| Provider | Words | Segments | Diarize | Language input | Max upload | Extensions |
| --- | --- | --- | --- | --- | --- | --- |
| `elevenlabs` | yes | yes | yes | ISO 639-1 or 639-3 | 5 GB | any |
| `aqua` | no | no | no | fixed provider list | 25 MB | flac, m4a, mp3, mp4, mpeg, mpga, ogg, wav, webm |
| `cohere` | no | no | no | fixed provider list | 25 MB | flac, mp3, mpeg, mpga, ogg, wav |
| `grok` | yes | yes | yes | fixed provider list | 500 MB | aac, flac, m4a, mkv, mp3, mp4, ogg, opus, wav |
| `openai` | yes | yes | yes | ISO 639-1 | 25 MB | m4a, mp3, mp4, mpeg, mpga, wav, webm |
| `meta` | no | yes | yes | language names | 32 MB | wav |
| `gemini` | yes | yes | yes | BCP-47 | no byte limit (one hour per file) | aac, aif, aiff, flac, m4a, mp3, mpeg, mpga, ogg, opus, wav, webm |
| `fish-audio` | yes | yes | yes | ISO 639-1 | no published byte limit (60 minutes per file) | aac, flac, m4a, mkv, mov, mp3, mp4, oga, ogg, opus, wav, webm |
| `apple` | yes | yes | no | `Locale` identifier | none | any |
| `voz` | yes | yes | no | none (on-device model) | none; nothing is uploaded | any |

Aqua and Cohere return text only, so `--format srt` or `--format vtt` with
either is a usage error rather than a wasted upload. Meta returns speaker
turns but no word timings, so `--words` is rejected there too. VOZ returns
words only, so its segments are built by the CLI: one per sentence by default,
or with `--cues segments` by the cue builder, where `--max-cue-duration` and
`--max-cue-chars` shape its subtitles.

Fish Audio returns speaker turns and words. SpeechKit copies the punctuation
from the turns onto the words and labels each word with its speaker, so Fish
Audio also defaults to one segment per sentence. `--cues segments` keeps its
speaker turns instead, which run as long as the speaker does. Every Fish Audio
run asks for timestamps, because the turns are empty without them. With
`--diarize` Fish Audio always labels speakers; without it, Fish Audio decides.
Its labels `speaker:0`, `speaker:1` become `0`, `1` in JSON, and `A`, `B` in
the other formats. AIFF and CAF, which Fish Audio rejects, fail before upload.

ElevenLabs defaults to Scribe v3 and labels each word with its speaker under
`--diarize`; the `speaker_0`, `speaker_1` labels reach the same formats Fish
Audio's do. `--speakers` caps how many speakers v3 looks for. On `scribe_v3`,
`--numbers` picks digits or words and `--secondary-language` names other
languages the audio may switch to; both are usage errors on the other models.
`--keyword` sends keyterms, `--tag-audio-events` marks sounds such as laughter,
and `--no-verbatim` drops filler words.

Use `speechkit languages <provider>` for the accepted `--language` values.
Grok, Aqua, Cohere, and Meta print a fixed list; OpenAI and Gemini accept any
code, and Fish Audio any two-letter ISO 639-1 code, so they print a note
instead; Apple prints the locales this machine's
transcriber actually supports; ElevenLabs takes any ISO 639-1 or 639-3 code
but sends only the first, and VOZ says the flag is ignored.
Region subtags such as `-US` are dropped before
matching against a fixed list, so `pt-BR` and `pt` resolve the same way.

### Flags dropped per provider

Flags that a provider cannot use are dropped rather than failing the run. The
note appears on stderr and in the `warnings` array of JSON output. With more
than one input file, the note is prefixed with the file it came from.

| Provider | Dropped |
| --- | --- |
| `elevenlabs` | `--prompt`; every `--language` after the first |
| `aqua` | `--timeout`, `--prompt`, `--keyword` |
| `cohere` | `--timeout`, `--prompt`, `--keyword` |
| `grok` | `--prompt`, `--keyword` |
| `openai` | `--prompt` under `gpt-4o-transcribe-diarize`, which takes none |
| `meta` | `--prompt` |
| `gemini` | `--prompt`; `--keyword` is dropped when combined with `--diarize` or `--words`, which Gemini rejects |
| `fish-audio` | `--prompt`, `--keyword`; every `--language` after the first |
| `apple` | `--model`, `--endpoint`, `--timeout`, `--prompt` |
| `voz` | `--model`, `--endpoint`, `--language`, `--timeout`, `--prompt`, `--keyword` |

Aqua, Cohere, and ElevenLabs also note that the transcript is a single untimed
segment, and Grok, Gemini, ElevenLabs, and Fish Audio note when the provider
returned no word timings and the transcript collapsed to one untimed segment.

## VOZ on-device model

`--provider voz` transcribes with the VOZ speech model through the
[SpeechKit-Voz](https://github.com/SENTINELITE/SpeechKit-Voz) package. No audio leaves the machine and no
API key is involved, but the model is not bundled: the first run downloads
about 337 MB, and the first load after that pays a one-time Neural Engine
specialization that can take several minutes.

Do the download once, deliberately, before you need it:

```sh
speechkit voz status              # model, whether it is cached, where it lives
speechkit voz status --json
speechkit voz prepare             # download if needed, then load once
speechkit voz prepare --download-only   # fetch the files without loading them
```

`voz status` is the default subcommand, so plain `speechkit voz` reports.

A `transcribe` run prepares the model itself if it has to, printing the size it
is about to fetch and then a progress line that is rewritten in place on a
terminal and printed every ten percent through a pipe. A script that must never
trigger the download passes `--no-download`, which exits with code 3 and points
at `speechkit voz prepare`:

```sh
speechkit transcribe talk.wav -p voz --no-download
speechkit transcribe *.m4a -p voz -f srt -o subs/ --jobs 2
```

One model is loaded per `transcribe` invocation and shared by every file in the
batch, however many `--jobs` are in flight, and it is released when the last
file finishes. Inference itself is serialized inside SpeechKit-Voz, so `--jobs`
overlaps file reading rather than running several Core ML sessions at once.

The model files live in the VOZ managed cache. SpeechKit-Voz resolves that
location internally and publishes no accessor for it, so `voz status` names the
cache rather than printing a path. The cache can be purged by the operating
system; a later run simply downloads it again.

VOZ runs one multilingual model that takes no language hint and reports no
language, so `--language` is dropped with a note and `speechkit languages voz`
says so. It returns word timings but no speaker labels or confidences, so
`--diarize` is a usage error and JSON output carries `"language": null`.

### License notice

The VOZ runtime and model are **not** Apache 2.0. They are licensed under the
Desert Ant Labs Source-Available License 1.0, which adds attribution,
device-count, redistribution, and model-training obligations to anything that
ships them, and the runtime may send the license's minimal device-counting
telemetry (the license says that telemetry excludes inputs, outputs, and user
content). Audio never leaves the machine either way. Read
[SpeechKit-Voz's NOTICE.md](https://github.com/SENTINELITE/SpeechKit-Voz/blob/main/NOTICE.md) and the full terms at
<https://license.desertant.com/1.0> before redistributing this tool.

## Output formats

**txt** — one sentence per line, each prefixed with its start time, and a
trailing newline:

```
 6:40.5  That night he was more tired than he ever had been.
 6:45.8  He ate an early supper.
12:13.3  It was a good thing he had not been hungry the night before.
```

Times are `m:ss.s`, or `h:mm:ss.s` past an hour, truncated to the tenth so a
line never claims to start after its first word, and padded so the text lines
up. A silence of more than 10 seconds between two sentences leaves a blank
line, so a long recording reads in sections. Sentences come from the word timings when the provider returned any (see
[Sentences](#sentences)), and from the provider's segments otherwise. With
`--diarize`, each line carries its speaker after the time, as `0:05.0  B: …`.
A transcript with no timings at all, from Aqua or Cohere, is written as prose.

`--no-timestamps` writes the transcript as prose instead: the text and a
trailing newline, or with `--diarize` one paragraph per speaker turn, prefixed
`A: `, `B: `, and so on, separated by a blank line. `bench` always writes prose.

**json** — the `TranscriptDocument`: provider, model, source file, text,
language, duration, segments, words, and warnings. Pretty-printed with sorted
keys. Providers that report what a transcription cost carry a `metrics` object
too: `processingSeconds` from VOZ, `billedSeconds` from OpenAI and Aqua, and
OpenAI's token counts. The key is absent for the providers that report none of
it, so nothing that read this output before has to change.

**srt** — cues numbered from one, `00:00:01,520 --> 00:00:04,640` timings with a
comma before the milliseconds, a blank line between cues, UTF-8 with LF endings
and no byte order mark. With `--diarize`, cue text is prefixed `[A] `.

**vtt** — a `WEBVTT` header followed by a `NOTE` block recording provider,
model, and language, then cues with `.` before the milliseconds. With
`--diarize`, cue text is a `<v A>` voice span. With `--words`, cues carry inline
timing tags — `How <00:00:01.900>is <00:00:02.100>the` — which players use to
highlight words as they are spoken; the first word of a cue carries no tag
because the cue start already covers it.

Cues are built from segments by default, and from sentences for VOZ.
`--cues words` writes one cue per word instead, for word-highlighting players;
it needs word timings, so pass `--words` with it. Lines are wrapped on word
boundaries at the `--max-cue-chars` limit.

### Sentences

`--cues sentences` replaces the segments with one per sentence, built from the
word timings, so `json`, `srt`, and `vtt` all carry the same sentences. It is
the default for VOZ, which returns words and no segments of its own, and for
Fish Audio, whose punctuated words split its long speaker turns cleanly. Plain text
uses the same rules whatever `--cues` says. A new sentence starts when:

- the previous word ends in `.`, `?`, `!`, or `…`, unless it is a common
  abbreviation such as `Mr.` or `Dr.`
- the speaker paused for more than 2 seconds after at least three words, and
  the next word is not lowercase. That catches trailing off without
  punctuation, while a lone "So" or "Um", or a clause that carries on in
  lowercase after the pause, stays on one line
- the speaker paused for more than 10 seconds, however short the sentence
- the speaker changes
- the sentence is past 160 characters and the previous word ends in `,`, `;`,
  `:`, or a dash
- the sentence would pass 300 characters or 30 seconds

The `--max-cue-*` limits do not apply to sentences, so a long sentence makes a
long subtitle cue; use `--cues segments` for subtitles sized for the screen.
With Grok, Gemini, OpenAI, or ElevenLabs, `--cues sentences` asks for word
timestamps the way subtitle formats do. Aqua, Cohere, and Meta return no word
timings, so it is a usage error there.

Subtitles are never guessed. If a transcript carries no timings, `srt` and `vtt`
fail for that file with a message naming the provider rather than inventing cue
times.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Every file succeeded. |
| 1 | Usage or configuration error found before any work: bad flag combination, unsupported capability, invalid model or language, missing or unreadable input, unsupported extension, oversized file, existing output, or no timing data for a subtitle format. |
| 2 | At least one file failed while others succeeded; the successful transcripts are still written and the failures are listed on stderr. |
| 3 | No credential for the provider, `--provider apple` on macOS 15, a VOZ model that cannot be downloaded or loaded, `--no-download` with an uncached VOZ model, or a keychain failure. Under `bench`, only when no provider could run at all. |

Transcripts go to standard output unless `--output` is passed. Progress,
warnings, and errors always go to standard error, so the tool stays pipeable.

## Progress output

On a terminal, work in flight is drawn on the bottom lines of standard error:
a spinner, what the task is doing, the elapsed time, and a bar with a
percentage where the fraction is known, such as the VOZ model download. With
`--jobs 3` there are three of those lines, one per file. A file that finishes
collapses into the line it would have printed anyway:

```
[2/5] talk.wav -> talk.srt (grok, 14.2 s)
⠹ [3/5] keynote.m4a transcribing 0:18
⠹ [4/5] interview.wav writing 0:11
```

Piped or redirected, there is no live area at all and no escape sequence is
written: a redirected run produces the same bytes it did before the renderer
existed, which is the per-file line under `--verbose` and silence otherwise.
`--quiet` suppresses the live area on a terminal too.

`Ctrl-C` clears the live area, restores the cursor, and exits 130, so an
interrupted run never leaves a hidden cursor behind. Resizing the terminal
re-measures it and the lines are truncated to fit rather than wrapped.

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
SPEECHKIT_VOZ_USE_LOCAL_SPEECHKIT=1 swift build -Xswiftc -warnings-as-errors
SPEECHKIT_VOZ_USE_LOCAL_SPEECHKIT=1 swift test
```

The unit suite is hermetic: no network, no keychain writes outside a temporary
in-memory store, no media fixtures, and no writes to the machine's own usage
history, which the tests redirect with `SPEECHKIT_HISTORY_DIR` or opt out of
with `--no-history`. Integration tests are disabled unless credentials are
present, so a plain `swift test` skips them rather than failing.

To enable them, export the key for each provider you want to exercise and run
the suite again. Each enabled test synthesises a short WAV with `say` and
`afconvert`, transcribes it, and checks the text:

```sh
export SPEECHKIT_OPENAI_API_KEY=sk-…
export SPEECHKIT_GROK_API_KEY=xai-…
swift test
```

The Fish Audio test also runs when only `FISH_API_KEY` is set, since that is
where the tool reads its key from as well.

The on-device Apple test needs no key, so it is gated on an explicit opt-in
instead:

```sh
SPEECHKIT_INTEGRATION=1 swift test
```

The VOZ integration test needs the model on disk and never downloads it, so it
runs only when both the switch is set and `speechkit voz prepare` has already
been run:

```sh
speechkit voz prepare
SPEECHKIT_VOZ_INTEGRATION=1 swift test
```

## License

SpeechKit CLI is distributed under [Apache 2.0](LICENSE). The VOZ runtime
and model are covered by the Desert Ant Labs Source-Available License.
See [third-party notices](NOTICE.md).
