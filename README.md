# speechkit

A macOS command-line tool that transcribes audio files with any
[SpeechKit](../SpeechKit) provider and writes plain text or JSON. Subtitles
(SRT, WebVTT) and the remaining providers arrive in later phases.

This is phase 1: the command skeleton, `txt` and `json` output, and runners for
Grok, OpenAI, and Apple's on-device Speech framework.

## Build

```sh
swift build -c release
cp .build/release/speechkit /usr/local/bin/speechkit
```

The package depends on `../SpeechKit` by path, so both checkouts must sit side
by side. Requires macOS 15; `--provider apple` requires macOS 26.

## Usage

```sh
# On-device transcription, JSON to stdout
speechkit transcribe talk.wav --provider apple --format json --stdout

# OpenAI with word timestamps, writing talk.json next to the input
speechkit transcribe talk.m4a --provider openai --language en --words --format json

# Grok, several files, text output into a directory
speechkit transcribe *.wav --provider grok --format txt --output-dir ./transcripts
```

Run `speechkit transcribe --help` for every flag. Flags for later phases
(`--format srt`, `--format vtt`, the remaining providers) are declared now and
report that they are not implemented yet rather than failing obscurely.

## Credentials

Resolution order is `--api-key`, then the environment, then the macOS Keychain
(phase 3):

| Provider | Environment variable |
| --- | --- |
| ElevenLabs | `SPEECHKIT_ELEVENLABS_API_KEY` |
| Aqua | `SPEECHKIT_AQUA_API_KEY` |
| Cohere | `SPEECHKIT_COHERE_API_KEY` |
| Grok | `SPEECHKIT_GROK_API_KEY` |
| OpenAI | `SPEECHKIT_OPENAI_API_KEY` |
| Meta | `SPEECHKIT_META_API_KEY` |
| Gemini | `SPEECHKIT_GEMINI_API_KEY` |
| Apple | none; runs on device |

`SPEECHKIT_PROVIDER` supplies the default for `--provider`.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Every file succeeded |
| 1 | Usage or configuration error before any work |
| 2 | At least one file failed; the others were still written |
| 3 | Credential missing, or the provider is unusable on this machine |
