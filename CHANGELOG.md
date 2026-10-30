# Changelog

## 0.11.0 — 2026-10-29

Fish Audio is a new provider: `-p fish-audio`, or `-p fish` for short.

- It transcribes with Transcribe 1 Pro (`transcribe-1-pro`, the only model)
  through SpeechKit's Fish Audio client, and returns word timings, speaker
  turns, the detected language, and the duration. Every run asks for
  timestamps, because the speaker turns that become the segments are empty
  without them.
- Words carry punctuation and a speaker, so `--cues` defaults to `sentences`
  for Fish Audio as it does for VOZ. `--cues segments` keeps Fish Audio's
  speaker turns, which can run long. Speaker labels `speaker:0` become `0`,
  as Grok's are, and formatters still print them as `A`, `B`.
- `--diarize` asks for speaker labels outright. Without it, Fish Audio decides
  for itself, its own default.
- `--language` sends one two-letter ISO 639-1 hint; `en-US` sends `en`. The
  hint helps detection but does not force the language. `--prompt` and
  `--keyword` are dropped with a note.
- The key comes from `--api-key`, `SPEECHKIT_FISH_AUDIO_API_KEY`,
  `FISH_API_KEY`, or the keychain under `fish-audio`, in that order. `keys`,
  `providers`, and `bench` all know it.
- Fish Audio accepts aac, flac, m4a, mov, mp3, mp4, oga, ogg, opus, wav, and
  webm. AIFF and CAF, which it rejects, fail before upload. Files over 60
  minutes fail in SpeechKit before upload. `--timeout` defaults to 15 minutes
  for Fish Audio, because it answers only once the whole file is done.
- Environment variable names replace a hyphen in the provider name with an
  underscore, so the name is one a shell can export.

## 0.10.2 — 2026-10-25

- A pause no longer breaks a sentence when the next word starts in lowercase,
  since VOZ capitalises the first word of a new sentence. "I just wish there
  was one", a pause, and "clear cut goalpost I could chase." is now one line.
  On the 35-minute test recording, lines broken mid-sentence went from 23 to
  13; the rest come before a capitalised word or a silence over 10 seconds.

## 0.10.1 — 2026-10-25

Smoother sentence text.

- A pause no longer splits off a sentence of one or two words. "How", a
  five-second pause, and "I'm just so tired." is now one line timed from
  "How". A pause longer than 10 seconds still splits, however short the line.
  On a 35-minute test recording this cut the one- and two-word lines without
  punctuation from 17 to 3.
- Timestamped `txt` leaves a blank line where the recording falls silent for
  more than 10 seconds, so it reads in paragraphs.
- VOZ now prints `loading model`, and adds the note about the Neural Engine
  only when loading has run for five seconds. A prepared model loads in under
  a second, so the note no longer appears on every run.

## 0.10.0 — 2026-10-25

Plain text is now one timestamped sentence per line, and VOZ transcripts are
split into sentences instead of pause-sized fragments.

- `txt` writes `6:45.8  He ate an early supper.`, one sentence per line, with
  times padded into a column. Sentences come from the word timings, or from the
  provider's segments when there are no words; a transcript with no timings is
  still written as prose. With `--diarize` the speaker follows the time.
  `--no-timestamps` restores the old prose output, and `bench` keeps writing
  prose.
- `--cues sentences` rebuilds the segments as one per sentence for every
  format, so `json`, `srt`, and `vtt` agree. A sentence ends at `.`, `?`, `!`,
  or `…` (not after `Mr.`, `Dr.`, and similar), at a pause longer than two
  seconds, at a speaker change, at a comma once it passes 160 characters, and
  in any case by 300 characters or 30 seconds. The `--max-cue-*` limits do not
  apply.
- `--cues` now defaults to `sentences` for VOZ and stays `segments` for every
  other provider. VOZ returns words only, and the old cue builder split them at
  0.8-second pauses, which cut sentences mid-clause.
- `--cues sentences` asks Grok, Gemini, OpenAI, and ElevenLabs for word
  timestamps, as subtitle formats do, and is a usage error on Aqua, Cohere, and
  Meta, which return none.

## 0.9.0 — 2026-09-15

`speechkit` with no arguments on a terminal now walks through a run with arrow
keys, and prints the headless command it assembled before running it.

- A bare `speechkit` routes to the new `interactive` command when standard
  input and standard error are both terminals. `speechkit interactive` and
  `speechkit ui` force it, and say what to run instead when there is no
  terminal. With any argument at all, and off a terminal, nothing changed:
  `transcribe` is still the default subcommand and a no-argument run in a
  script still prints the same usage error.
- The transcribe flow asks for the provider, the files, the formats, word
  timestamps, speaker labels, and the output destination, in that order, and
  skips the questions the chosen provider cannot answer. Providers are listed
  with their status: `on device, ready`, `on device, model not downloaded`,
  `key: keychain`, `key: env`, or `no key`. The file step lists the audio files
  in the current directory, with a path prompt behind an `Enter a path…` row
  that completes with tab and expands globs. `stdout` is offered only for one
  file in one format.
- Before anything runs, the assembled command is printed as it could be pasted
  into a shell, with paths quoted, and can be copied with `pbcopy`. Choosing to
  run it parses that same command line and runs it, so validation, output,
  progress, usage history, and exit codes are the headless ones. There is no
  second implementation of a run.
- Provider, formats, and output directory are prefilled from the last
  successful `transcribe` in the usage history. A machine with no history is
  offered VOZ when its model is downloaded, Apple on macOS 26, and otherwise
  the first provider with a key. `transcribe` now records the `--output`
  directory it wrote into, which is the field that default reads.
- A provider with no key drops into a hidden key prompt that writes to the
  keychain through the same code as `keys set`, and comes back. VOZ asks before
  downloading its model. The first question also offers key management and VOZ
  preparation on their own.
- The bench flow collects providers (including `all`), files, formats, an
  optional reference directory, a repeat count, and an output directory.
- Escape steps back one question, and escape at the first one leaves. `Ctrl-C`
  and `Ctrl-D` restore the terminal and exit 130, coordinated with the progress
  renderer's interrupt handling so the raw mode and the live area are both
  undone once. Prompts draw on standard error only.

## 0.8.0 — 2026-09-15

Work in flight is drawn live on a terminal, and piped output is unchanged.

- A single `ProgressRenderer` owns the bottom lines of standard error. Each
  task in flight gets a row with a spinner, its label, and its elapsed time,
  and a twenty-cell bar with a percentage once a fraction is known. Frames are
  drawn at most twelve times a second, and only when something changed or a
  quarter second has passed.
- `transcribe` and `bench` draw one row per file, so `--jobs 3` shows three.
  A file moves from `transcribing` to `writing`, and its row collapses into
  the `[2/5] talk.wav -> talk.srt (grok, 14.2 s)` line it always printed,
  written above the live area so scrollback reads exactly like a piped run.
  `--repeat` counts its passes in the label.
- VOZ model preparation is one row: `checking cached model files`,
  `downloading 196 MB of 467 MB` with a bar, then `loading model` with the
  elapsed time that first load needs. `keys check --live` draws one row per
  provider being probed.
- Rows are truncated to the terminal width, which is re-read on `SIGWINCH`, so
  a narrow window never wraps a live line. Warnings, notes, and errors clear
  the live area, print where it was, and let the next frame redraw underneath.
- `Ctrl-C` clears the live area, restores the cursor, and exits 130.
- Nothing changes when standard error is not a terminal, or under `--quiet`:
  no escape sequence is written, and the same lines come out in the same
  order. Upload percentages are not among the phases, because SpeechKit's
  `URLSession` is internal to the package and there is no way to observe an
  upload from outside it.

## 0.7.0 — 2026-09-15

Every run is recorded locally, and `speechkit stats` and `speechkit history`
report on them.

- `transcribe`, `bench`, and `keys check --live` append one JSON Lines record
  per file per provider to `~/Library/Application Support/speechkit/history.jsonl`.
  The record carries the timestamp, CLI version, command, provider, model,
  input name, path and size, audio seconds, wall seconds, realtime factor,
  words, characters, formats written, the `--words`, `--diarize`, and
  `--repeat` settings, and either `ok` or a short error class with the first
  line of the failure. Transcript text, API keys, and reference transcripts are
  never recorded.
- The store is an actor over an append-only file, and each record is written as
  one whole line, so a batch of concurrent uploads produces one intact line
  each. The directory is created `0700` and the file `0600`. A line that cannot
  be read is skipped with a single warning, and recording can never fail a run:
  a store that cannot be written is a `--verbose` note and nothing more.
- `speechkit stats` prints audio transcribed, wall time, realtime factor,
  words, the most used commands and providers, and the fastest and slowest
  provider. `--since` takes `24h`, `7d`, `30d`, or a date; `--by provider`,
  `--by command`, and `--by day` group the rows; `--json` emits the totals and
  every grouping as one object. An empty history prints one line and exits 0.
- Realtime factors are computed from the totals, never averaged over the rows,
  so a two-second clip cannot outweigh a two-hour recording.
- `speechkit history` lists the runs themselves, newest first, with `--limit`,
  `--provider`, `--failed`, `--since`, and `--json`. `speechkit history clear`
  deletes the file after a confirmation, and requires `--yes` when standard
  input is not a terminal.
- `--no-history` on `transcribe`, `bench`, and `keys check`, and
  `SPEECHKIT_NO_HISTORY` set to anything non-empty, record nothing at all:
  neither the file nor its directory is created. `SPEECHKIT_HISTORY_DIR` moves
  the history somewhere else.

## 0.6.0 — 2026-09-15

`speechkit bench` compares providers over the same audio, and `speechkit keys
check` verifies credentials in bulk.

- `speechkit keys check [providers...]` reports where every provider's API key
  comes from (environment, keychain, none, or not needed) as a table or
  `--json`, with keys redacted. `--live` verifies each key by transcribing a
  short generated clip, adding status, timing, and error detail. Exits `0`
  when every requested provider is usable, `2` when a live check failed, and
  `3` when a key is missing.

- `speechkit bench <files or folders> -p <provider> ... -o <directory>` runs the
  same recordings through several providers and writes `<stem>.<provider>.txt`
  for reading side by side, plus `summary.csv`, `summary.md`, and
  `summary.json`. A directory argument contributes its audio files, and
  `--recursive` reaches the subdirectories.
- Each row reports wall time, the realtime factor, the provider's own processing
  and billing numbers, characters, words, an estimated token count, bytes,
  segments, whether there are word timings, and the word error rate. Only the
  provider call is timed, with `ContinuousClock`; validating, formatting, and
  writing happen outside the clock.
- `--reference-dir` scores each transcript against a `<stem>.txt` reference with
  a word-level Levenshtein distance over lowercased, depunctuated text. A
  `<stem>.reference.txt` beside the input works without the flag.
- `-p all` runs every provider that has a credential or needs none. A named
  provider without one is a warning and a skip; the run exits 3 only when
  nothing could run. A file one provider rejects is a failed row rather than a
  failed run, and any failed row exits 2.
- `--repeat N` transcribes each file N times per provider and reports the mean
  and the fastest. `--jobs` defaults to 1, so timings are not measured against
  each other.
- VOZ prepares its model once per provider pass. That cost is reported as
  `setup_seconds` beside the aggregate rather than charged to the first file.
- `TranscriptDocument` gains an optional `metrics` object carrying
  `processingSeconds` (VOZ), `billedSeconds` (OpenAI, Aqua), and OpenAI's token
  counts. It is omitted from JSON output entirely when a provider reports none
  of it.

## 0.5.0 — 2026-09-15

The on-device VOZ model joins the provider list.

- `--provider voz` transcribes locally through the SpeechKit-Voz package, with
  word timings and cue-built segments, no API key, and no audio leaving the
  machine. The model is not bundled: the first use downloads roughly 467 MB.
- `speechkit voz status` reports whether the model is cached, and
  `speechkit voz prepare` downloads and loads it once ahead of time.
  `--download-only` fetches the files without loading them.
- `speechkit transcribe --no-download` exits with code 3 and points at
  `speechkit voz prepare` rather than starting a surprise download.
- A batch loads one model and shares it across every `--jobs` worker, then
  releases it when the last file finishes.
- `--model`, `--endpoint`, `--language`, `--timeout`, `--prompt`, and
  `--keyword` are dropped with a note under `voz`, and `--diarize` is a usage
  error. `speechkit providers` and `speechkit languages voz` describe all of it.
- The VOZ runtime and model are under the Desert Ant Labs Source-Available
  License, not Apache 2.0. See the license notice in the README.

## 0.4.0 — 2026-09-15

Output goes to stdout by default.

- `speechkit transcribe` prints the transcript to standard output unless
  `--output` is passed. One input file and one format fit on stdout; more than
  that is a usage error that points at `--output <directory>`.
- `-o`, `--output` now takes either a directory (existing, or ending with `/`)
  or a single file path. `--output-dir` and `--stdout` are gone.

## 0.3.1 — 2026-09-15

Review fixes across option handling, output, and subtitles.

- OpenAI now reconciles `--model` with `--words`, `--diarize`, and `--prompt`
  before the upload: word timestamps select `whisper-1`, speaker labels select
  `gpt-4o-transcribe-diarize`, that model's prompt is dropped with a note, and a
  model that cannot serve the flags is a usage error rather than a rejected
  request.
- `--format srt` and `--format vtt` ask Grok, Gemini, OpenAI, and ElevenLabs for
  word timestamps, so subtitles no longer fail with "no timing data" after a
  successful upload.
- `--max-cue-duration` and `--max-cue-chars` now reach the Gemini and ElevenLabs
  segment builders.
- Two inputs that would write to the same path are refused before any upload,
  and `--output-dir` can no longer be combined with `--output` or `--stdout`.
- A skipped output reads as `talk.txt (exists, skipped)` in the progress line
  instead of looking like a write. The run still exits 0.
- WebVTT escapes `&`, `<`, and `>` in cue text, and `NOTE` values lose their line
  breaks and cue arrows.
- Provider notes print at normal verbosity, prefixed with the file name in a
  multi-file run, rather than hiding behind `--verbose`.
- Every provider validates `--model` and `--language` before the first upload,
  so a bad value always exits 1. Apple checks `--language` against the locales
  this machine's transcriber supports and reports BCP-47 language tags.
- Grok notes that it drops `--prompt` and `--keyword`. Provider segments are
  sorted by start, and a segment ending before it starts is dropped.
- `speechkit bogus` explains that the argument is not a file and points at
  `speechkit --help`.
- Removed `--raw`, which no provider could serve, along with the eight warnings
  it produced.

## 0.3.0 — 2026-09-15

First working version of the `speechkit` command-line tool.

- `speechkit transcribe` for one or more audio files with any of the eight
  SpeechKit file providers: ElevenLabs, Aqua, Cohere, Grok, OpenAI, Meta,
  Gemini, and Apple's on-device Speech framework. Provider responses are mapped
  into one neutral `TranscriptDocument`.
- Output as `txt`, `json`, `srt`, or `vtt`, several formats at once, to a file,
  a directory, or standard output. Speaker labels with `--diarize`, word
  timestamps with `--words`, inline WebVTT word timing tags, `--cues words` for
  one cue per word, and `--max-cue-duration` and `--max-cue-chars` limits on the
  cue builder.
- `--language` mapped per provider, with region subtags dropped for providers
  that take a fixed list, and `--model`, `--endpoint`, `--timeout`, `--prompt`,
  and `--keyword` passed through where the provider accepts them and dropped
  with a recorded note where it does not.
- Credentials from `--api-key`, `SPEECHKIT_<PROVIDER>_API_KEY`, or the login
  keychain, managed with `speechkit keys set|get|delete|list`. Keys are read
  from a hidden prompt or `--from-stdin` and never appear in shell history.
- `speechkit providers` and `speechkit languages <provider>` for capability and
  language discovery, both with `--json`.
- Batch runs with `--jobs`, per-file failures that do not cancel the rest,
  `--overwrite`, stderr progress, and exit codes 0, 1, 2, and 3.
- Pre-upload validation of capabilities, models, languages, file existence,
  extension, and size, so a rejected run costs no upload.
