# Changelog

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
