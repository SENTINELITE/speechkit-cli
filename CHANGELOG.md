# Changelog

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
