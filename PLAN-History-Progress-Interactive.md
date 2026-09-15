# Plan: usage history, live progress, and interactive mode

Date: 2026-09-15. Repository: `speechkit-cli`, building on version 0.6.0.

Three features, in the order they should land, because each one feeds the next: the history store gives the interactive mode something to show, and the progress renderer is what the interactive mode runs on top of.

1. **Usage history and `stats`.** Every run is recorded locally; `speechkit stats` and `speechkit history` show totals and trends.
2. **Live progress.** Spinners, bars, and elapsed timers on a TTY, replacing the static waits during VOZ model loading, uploads, and long transcriptions.
3. **Interactive mode.** `speechkit` with no arguments on a terminal walks through provider, files, formats, and options with arrow keys, shows the equivalent headless command, and runs it. Headless mode stays exactly as it is.

No new dependencies. All three use Foundation, Darwin `termios`, and ANSI escape sequences. That keeps the build fast and the binary self-contained.

## 1. Usage history and `stats`

### Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Storage | Append-only JSON Lines at `~/Library/Application Support/speechkit/history.jsonl`, one object per file per run. | Human-readable, greppable, trivially appended from concurrent batch tasks with one `FileHandle` under a lock, no schema migrations. SQLite is the upgrade if the file ever passes tens of thousands of rows; reading it takes a few milliseconds at that size. |
| What is recorded | Command (`transcribe`, `bench`, `keys check`), provider, model, input file name and full path, input bytes, audio seconds, wall seconds of the provider call, words, characters, formats written, status (`ok` or the error class), timestamp, CLI version, `--words` and `--diarize` flags, `--repeat` count for bench. | Everything `stats` needs to answer the questions asked: most-used commands and providers, files transcribed, total words, total wall time, realtime factor, and how those move over time. |
| What is never recorded | Transcript text, API keys, reference transcripts, WER (it depends on a file the user owns and can rerun). | The history file is not a second copy of anyone's audio content. |
| Opt-out | `--no-history` on any command, or `SPEECHKIT_NO_HISTORY=1`. `speechkit history clear` deletes the file after a confirmation, `--yes` skips it. | Scripts and shared machines. |
| Realtime factor | Computed at read time as total audio seconds divided by total wall seconds, so a 100-minute file done in 20 seconds reports `300x`. Per-row factor is also stored for the sort. | Aggregating factors by averaging them is wrong; totals are right. |

### Commands

```
speechkit stats                       # overall summary since the first record
speechkit stats --since 7d            # also 24h, 30d, 2026-09-01
speechkit stats --by provider         # provider | runs | files | audio | wall | realtime | words | failures
speechkit stats --by command
speechkit stats --by day --since 30d  # one row per day, for trends
speechkit stats --json
speechkit history                     # last 20 rows, newest first
speechkit history --limit 100 --provider voz --failed
speechkit history clear
```

`stats` default output:

```
Since 2026-09-15 (3 days), 41 runs, 38 files, 3 failures
Audio transcribed     6 h 12 m
Wall time             4 m 51 s
Realtime factor       76.7x
Words                 58,310
Most used commands    transcribe 31, bench 8, keys check 2
Most used providers   voz 19, apple 12, grok 7
Fastest provider      voz 141x   Slowest  grok 9.8x
```

### Code

- `Support/HistoryStore.swift`: `HistoryRecord: Codable`, `HistoryStore` (append, read all, clear, path resolution with an injectable root directory for tests), an `actor` around the file handle so batch tasks can append concurrently.
- `Support/HistoryReport.swift`: filtering, grouping, duration and number formatting, the table and JSON renderers. Pure functions over `[HistoryRecord]` so they test with fixtures.
- `Commands/Stats.swift`, `Commands/History.swift`.
- Recording hooks: `Transcribe.run(file:)` and `Bench` already produce a per-file outcome with timing and word counts; each gets one `history.append(...)` call. `keys check --live` records one row per provider with the probe timing.
- Tests: append and read round trip, concurrent appends from a task group produce N intact lines, `--since` parsing, grouping tables as golden strings, realtime factor from totals not averages, opt-out flag and env var, `clear` refuses without `--yes` when stdin is not a TTY.

Half a day to a day.

## 2. Live progress

### Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Where it renders | Standard error only, only when stderr is a TTY and `--quiet` is off. When piped, the current plain lines stay exactly as they are. | Transcripts on stdout must stay clean, and logs must stay greppable. |
| One renderer | A single `ProgressRenderer` actor owns the bottom lines of the terminal. Everything else posts state changes to it; nothing else writes escape sequences. | Concurrent batch tasks and the VOZ state stream would otherwise fight over the cursor. |
| What it shows | One line per in-flight task, a spinner, the task label, elapsed time, and a bar with percent when a fraction is known (VOZ download, file upload via `URLSessionTaskDelegate` progress). Completed tasks collapse into the existing `[2/5] talk.wav -> talk.srt (grok, 14.2 s)` line above the live area. | Matches what `cargo`, `docker`, and `npm` do; users already read it. |
| Frame rate | 12 frames per second, redrawn only when state changed or 250 ms passed (for the elapsed timer). | Cheap, and no flicker. |
| Wide and narrow terminals | Truncate labels to the column count from `ioctl(TIOCGWINSZ)`; re-read on `SIGWINCH`. | A wrapped live line corrupts the redraw. |
| Interrupt | On `SIGINT`, clear the live area, restore the cursor, then exit 130. | Leaving a hidden cursor is the classic CLI bug. |

### Phases each command reports

- `transcribe` and `bench`: per file `validating`, `uploading 43%` (cloud), `transcribing` with elapsed time, `writing`. With `--jobs 3`, three live lines.
- VOZ: `checking cache`, `downloading 42% 196 MB of 467 MB`, `loading model` with elapsed time (this is the long one on first run), `ready`. Driven by `stateUpdates`, which `VozModelSession` already consumes.
- `keys check --live`: one line per provider being probed.
- Apple: `preparing assets` when SpeechKit downloads a locale, then `transcribing`.

### Code

- `Support/ProgressRenderer.swift`: the actor, the ANSI drawing (save cursor, clear below, redraw N lines, restore), spinner frames, bar, terminal width, signal handling via `DispatchSource.makeSignalSource`.
- `Support/Console.swift` gains `func task(_ label: String) -> ProgressTask` returning a handle with `update(fraction:)`, `update(label:)`, `finish(line:)`, and `fail(line:)`. When not a TTY, the handle prints `finish` and `fail` lines only, which is today's behaviour. Every existing `console.progress` call site becomes a task handle. `RunContext.console` already reaches every runner, so runners post phase changes without new plumbing.
- Upload progress: the cloud runners go through SpeechKit's `URLSession`; `SpeechService` takes a `urlSession`, so the CLI can supply one whose delegate reports `didSendBodyData` per task and maps it to the right file by task identifier. If that turns out to be awkward inside SpeechKit's multipart path, the fallback is a spinner with elapsed time for uploads, which is still an improvement.
- Tests: the renderer takes an injectable output sink and width, so tests assert the exact byte sequence for one frame, the collapse-on-finish behaviour, truncation at 40 columns, and that a non-TTY console emits only finish lines.

One to two days. Upload percentages are the uncertain part.

## 3. Interactive mode

### Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Entry | `speechkit` with no arguments when stdin and stderr are TTYs. `speechkit interactive` (alias `ui`) forces it; `speechkit --help` and any subcommand stay headless. Not a TTY and no arguments prints the usage error it prints today. | Discoverable, and it can never hijack a script. |
| Scope of v1 | Transcribe and bench flows, key setup when a chosen provider has no key, VOZ download when chosen and not cached. Not a full-screen app: a sequence of prompts that scroll like `npm init`, each prompt clearing itself when answered. | Covers what people type most, and stays small. |
| Show the command | Before running, print the exact headless command line the choices produce, and offer to copy it. | Makes the interactive mode a teacher for the flags, and every run is reproducible. |
| Prompt kinds | Single select (arrow keys, `j`/`k`, type-to-filter, enter), multi select (space toggles, enter confirms), text with a default, path with tab completion against the file system, yes/no. | Everything the flag set needs. |
| Defaults | Prefilled from history: last provider, last output directory, last formats. First run falls back to VOZ if cached, else Apple on macOS 26, else the first provider with a key. | This is where section 1 pays off. |
| Escape and Ctrl-C | Escape goes back one prompt; Ctrl-C restores the terminal and exits 130. | Standard. |

### Flow

```
? What do you want to do?            › Transcribe files   Benchmark providers   Manage keys   Prepare VOZ
? Provider                           › voz (on device, ready)   apple   grok (key: keychain)   openai (no key)  ...
? Files                              › drag files here or type a path; globs allowed        [tab completes]
? Formats                            ◉ txt  ◯ json  ◉ srt  ◯ vtt
? Word timestamps?                   Yes / No
? Speaker labels?                    (hidden when the provider cannot)
? Output                             › stdout   next to the inputs   choose a directory…
                                     speechkit transcribe a.m4a b.m4a -p voz -f txt -f srt -o ./out/
? Run it?                            Yes / Copy command / Back
```

Choosing a provider with no key jumps to the `keys set` prompt inline. Choosing VOZ when the model is not cached asks before downloading and then shows the download bar from section 2. Bench adds a providers multi-select with `all`, a reference directory prompt, and a repeat count.

### Code

- `Support/Terminal.swift`: raw mode on and off with `termios`, key reading that decodes arrow keys, escape, enter, space, backspace, tab, Ctrl-C, and printable characters, with a `defer` that always restores the terminal. Cursor show and hide.
- `Support/Prompts.swift`: `SelectPrompt`, `MultiSelectPrompt`, `TextPrompt`, `PathPrompt`, `ConfirmPrompt`. Each is a pure state machine (`apply(key:) -> State`) plus a renderer, so tests drive them with key sequences and assert the result without a terminal.
- `Commands/Interactive.swift`: the flows above, ending in a `Transcribe` or `Bench` value built through `parse([...])` from the assembled arguments. This is the important design point: interactive mode produces the same command struct the headless path uses, so there is one code path for validation, running, output, and history.
- `SpeechKitCommand.swift`: detect the no-argument TTY case before ArgumentParser sees it, and route to `Interactive`.
- Tests: prompt state machines with key sequences (filtering, wrap-around, multi-select toggles, tab completion against a temp directory), the argument assembly for a representative set of choices, the no-arguments routing on TTY and not.

Two to three days.

## Order and versions

| Version | Contents |
| --- | --- |
| 0.7.0 | History store, `stats`, `history`, opt-out. |
| 0.8.0 | Progress renderer wired into transcribe, bench, VOZ, keys check. |
| 0.9.0 | Interactive mode with transcribe and bench flows. |

Each version is one Opus agent with a brief like the earlier phases, followed by the same review-and-fix pass that caught the OpenAI and VTT bugs last time.

## Open questions

1. Should `stats` also count audio minutes per provider as an estimate of spend? Only OpenAI and Aqua report billed seconds; the rest would be the audio duration. Recommendation: yes, labelled as audio minutes, not cost.
2. Interactive file selection: a path prompt with tab completion, or a browser that lists audio files in the current directory with arrows? Recommendation: both, with the browser as the default when the current directory has audio files.
3. Should the interactive mode remember answers per directory (a `.speechkit.json` next to the recordings) so a project folder reopens with its own provider and formats? Recommendation: defer; history-based defaults cover most of it.
