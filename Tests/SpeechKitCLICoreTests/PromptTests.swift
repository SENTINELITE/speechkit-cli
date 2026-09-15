import Foundation
import Testing
@testable import SpeechKitCLICore

/// The prompt state machines, driven by key sequences rather than a terminal.
@Suite("Prompts")
struct PromptTests {
    /// Turns a string into the keys a user would press to type it.
    private func typing(_ text: String) -> [Key] {
        text.map { $0 == " " ? Key.space : Key.character($0) }
    }

    /// Applies keys in order and returns the last outcome.
    @discardableResult
    private func drive<P: Prompt>(_ prompt: inout P, _ keys: [Key]) -> PromptOutcome<P.Value> {
        var outcome = PromptOutcome<P.Value>.continue
        for key in keys {
            outcome = prompt.apply(key)
            if outcome != .continue { return outcome }
        }
        return outcome
    }

    private var providers: [SelectItem] {
        [
            SelectItem(id: "elevenlabs", title: "elevenlabs", detail: "no key"),
            SelectItem(id: "grok", title: "grok", detail: "key: keychain"),
            SelectItem(id: "openai", title: "openai", detail: "key: env"),
            SelectItem(id: "voz", title: "voz", detail: "on device, ready")
        ]
    }

    // MARK: - Select

    @Test("Arrow keys wrap around both ends of the list")
    func selectWraps() {
        var prompt = SelectPrompt(title: "Provider", items: providers)
        #expect(prompt.index == 0)
        drive(&prompt, [.up])
        #expect(prompt.index == 3)
        drive(&prompt, [.down])
        #expect(prompt.index == 0)
        #expect(drive(&prompt, [.character("j"), .enter]) == .submit("grok"))
    }

    @Test("Typing filters the list, and backspace widens it again")
    func selectFilters() {
        var prompt = SelectPrompt(title: "Provider", items: providers)
        drive(&prompt, typing("o"))
        // Both openai and voz contain an o; grok does too.
        #expect(prompt.visibleItems.map(\.id) == ["grok", "openai", "voz"])
        drive(&prompt, typing("pen"))
        #expect(prompt.filter == "open")
        #expect(prompt.visibleItems.map(\.id) == ["openai"])
        #expect(prompt.index == 0)

        drive(&prompt, [.backspace, .backspace, .backspace, .backspace])
        #expect(prompt.filter.isEmpty)
        #expect(prompt.visibleItems.count == 4)
    }

    @Test("Enter submits the highlighted row of the filtered list")
    func selectSubmitsFiltered() {
        var prompt = SelectPrompt(title: "Provider", items: providers)
        #expect(drive(&prompt, typing("vo") + [.enter]) == .submit("voz"))
    }

    @Test("Filtering keeps the highlight inside the visible rows")
    func selectFilterResetsIndex() {
        var prompt = SelectPrompt(title: "Provider", items: providers, selectedID: "voz")
        #expect(prompt.index == 3)
        drive(&prompt, typing("grok"))
        #expect(prompt.index == 0)
        #expect(drive(&prompt, [.enter]) == .submit("grok"))
    }

    @Test("A filter that matches nothing submits nothing")
    func selectEmptyFilter() {
        var prompt = SelectPrompt(title: "Provider", items: providers)
        drive(&prompt, typing("zzz"))
        #expect(prompt.visibleItems.isEmpty)
        #expect(prompt.apply(.enter) == .continue)
        #expect(prompt.render(width: 40).contains("  no matches"))
    }

    @Test("Escape steps back and Ctrl-C cancels")
    func selectEscapeAndCancel() {
        var prompt = SelectPrompt(title: "Provider", items: providers)
        #expect(prompt.apply(.escape) == .back)
        #expect(prompt.apply(.controlC) == .cancel)
        #expect(prompt.apply(.controlD) == .cancel)
    }

    @Test("A select prompt draws a pointer, the status, and the summary it leaves")
    func selectRendering() {
        let prompt = SelectPrompt(title: "Provider", items: providers, selectedID: "voz")
        let lines = prompt.render(width: 60)
        #expect(lines[0] == "? Provider")
        #expect(lines[1] == "  elevenlabs  (no key)")
        #expect(lines[4] == "› voz  (on device, ready)")
        #expect(prompt.summary(for: "voz") == "? Provider  voz")
    }

    // MARK: - Multi select

    @Test("Space toggles rows and enter submits them in list order")
    func multiSelectToggles() {
        let formats = OutputFormat.allCases.map { SelectItem($0.rawValue) }
        var prompt = MultiSelectPrompt(title: "Formats", items: formats)
        // srt first, then txt: the answer still comes back in list order.
        drive(&prompt, [.down, .down, .space, .up, .up, .space])
        #expect(prompt.selected == ["srt", "txt"])
        #expect(drive(&prompt, [.enter]) == .submit(["txt", "srt"]))
    }

    @Test("Space toggles a row off again")
    func multiSelectUntoggles() {
        let formats = OutputFormat.allCases.map { SelectItem($0.rawValue) }
        var prompt = MultiSelectPrompt(title: "Formats", items: formats, selectedIDs: ["txt", "json"])
        drive(&prompt, [.space])
        #expect(prompt.chosen == ["json"])
        #expect(drive(&prompt, [.enter]) == .submit(["json"]))
    }

    @Test("An empty multi-select refuses to submit unless it is allowed to")
    func multiSelectRefusesEmpty() {
        let formats = OutputFormat.allCases.map { SelectItem($0.rawValue) }
        var required = MultiSelectPrompt(title: "Formats", items: formats)
        #expect(required.apply(.enter) == .continue)

        var optional = MultiSelectPrompt(title: "Formats", items: formats, allowsEmpty: true)
        #expect(optional.apply(.enter) == .submit([]))
    }

    @Test("A multi-select filters on typing and toggles what the filter shows")
    func multiSelectFilters() {
        var prompt = MultiSelectPrompt(title: "Files", items: [
            SelectItem("intro.wav"), SelectItem("talk.wav"), SelectItem("notes.m4a")
        ])
        drive(&prompt, typing("wav"))
        #expect(prompt.visibleItems.map(\.id) == ["intro.wav", "talk.wav"])
        drive(&prompt, [.down, .space])
        #expect(drive(&prompt, [.enter]) == .submit(["talk.wav"]))
    }

    @Test("A multi-select draws a filled mark for each chosen row")
    func multiSelectRendering() {
        let prompt = MultiSelectPrompt(
            title: "Formats",
            items: OutputFormat.allCases.map { SelectItem($0.rawValue) },
            selectedIDs: ["txt", "srt"]
        )
        let lines = prompt.render(width: 60)
        #expect(lines[0] == "? Formats  space toggles, enter confirms")
        #expect(lines[1] == "› ◉ txt")
        #expect(lines[2] == "  ◯ json")
        #expect(lines[3] == "  ◉ srt")
        #expect(prompt.summary(for: ["txt", "srt"]) == "? Formats  txt, srt")
    }

    // MARK: - Text

    @Test("Text is edited with backspace and the cursor keys")
    func textEditing() {
        var prompt = TextPrompt(title: "Repeat count")
        drive(&prompt, typing("13"))
        #expect(prompt.text == "13")
        drive(&prompt, [.backspace])
        #expect(prompt.text == "1")
        drive(&prompt, typing("0"))
        drive(&prompt, [.left, .character("2")])
        #expect(prompt.text == "120")
        #expect(prompt.cursor == 2)
        #expect(drive(&prompt, [.enter]) == .submit("120"))
    }

    @Test("Enter on an empty line submits the default, and waits when there is none")
    func textDefault() {
        var withDefault = TextPrompt(title: "Repeat count", defaultValue: "1")
        #expect(withDefault.apply(.enter) == .submit("1"))
        #expect(withDefault.render(width: 40) == ["? Repeat count  (1)"])

        var withoutDefault = TextPrompt(title: "API key")
        #expect(withoutDefault.apply(.enter) == .continue)
    }

    @Test("A secret prompt draws bullets and never shows the key")
    func textSecret() {
        var prompt = TextPrompt(title: "API key for grok", isSecret: true)
        drive(&prompt, typing("sk-abc"))
        #expect(prompt.render(width: 40) == ["? API key for grok  ••••••"])
        #expect(prompt.summary(for: "sk-abc") == "? API key for grok  ••••••")
        #expect(drive(&prompt, [.enter]) == .submit("sk-abc"))
    }

    @Test("Text prompts step back on escape and cancel on Ctrl-C")
    func textEscape() {
        var prompt = TextPrompt(title: "Repeat count", defaultValue: "1")
        #expect(prompt.apply(.escape) == .back)
        #expect(prompt.apply(.controlC) == .cancel)
    }

    // MARK: - Path

    /// A temporary directory holding a few files to complete against.
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["talk-one.wav", "talk-two.wav", "notes.txt"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("clips", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    @Test("Tab completes to the only match")
    func pathCompletesOneMatch() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        var prompt = PathPrompt(title: "Files", lister: PathPrompt.fileSystemLister)
        drive(&prompt, typing(root.path + "/no"))
        drive(&prompt, [.tab])
        #expect(prompt.text == root.path + "/notes.txt")
        #expect(prompt.matches.isEmpty)
        #expect(drive(&prompt, [.enter]) == .submit(root.path + "/notes.txt"))
    }

    @Test("Tab extends to the common prefix and lists what is left")
    func pathCompletesSeveral() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        var prompt = PathPrompt(title: "Files", lister: PathPrompt.fileSystemLister)
        drive(&prompt, typing(root.path + "/t"))
        drive(&prompt, [.tab])
        #expect(prompt.text == root.path + "/talk-")
        #expect(prompt.matches.map { ($0 as NSString).lastPathComponent } == ["talk-one.wav", "talk-two.wav"])
        #expect(prompt.render(width: 80).count == 3)
    }

    @Test("A directory completes with a slash, so a second tab walks into it")
    func pathCompletesDirectory() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        var prompt = PathPrompt(title: "Files", lister: PathPrompt.fileSystemLister)
        drive(&prompt, typing(root.path + "/cl"))
        drive(&prompt, [.tab])
        #expect(prompt.text == root.path + "/clips/")
    }

    @Test("At most eight completions are listed, with a count for the rest")
    func pathCapsMatches() {
        let names = (1...12).map { "/tmp/clip\($0).wav" }
        var prompt = PathPrompt(title: "Files", lister: { _ in names })
        drive(&prompt, typing("/tmp/clip"))
        drive(&prompt, [.tab])
        #expect(prompt.matches.count == PathPrompt.maxMatches)
        #expect(prompt.matchCount == 12)
        #expect(prompt.render(width: 60).last == "    … 4 more")
    }

    @Test("Typing after a tab clears the stale completions")
    func pathClearsMatches() {
        var prompt = PathPrompt(title: "Files", lister: { _ in ["/tmp/a.wav", "/tmp/b.wav"] })
        drive(&prompt, [.tab])
        #expect(prompt.matches.count == 2)
        drive(&prompt, typing("x"))
        #expect(prompt.matches.isEmpty)
    }

    @Test("An empty path prompt waits rather than submitting nothing")
    func pathRefusesEmpty() {
        var prompt = PathPrompt(title: "Files", lister: { _ in [] })
        #expect(prompt.apply(.enter) == .continue)
        #expect(prompt.apply(.escape) == .back)
    }

    // MARK: - Confirm

    @Test("y and n answer a confirmation outright")
    func confirmLetters() {
        var prompt = ConfirmPrompt(title: "Word timestamps?")
        #expect(prompt.apply(.character("y")) == .submit(true))
        #expect(prompt.apply(.character("N")) == .submit(false))
    }

    @Test("The arrow keys toggle and enter takes the highlighted answer")
    func confirmArrows() {
        var prompt = ConfirmPrompt(title: "Word timestamps?", value: false)
        #expect(prompt.render(width: 40) == ["? Word timestamps?   Yes › No"])
        drive(&prompt, [.right])
        #expect(prompt.value)
        #expect(drive(&prompt, [.enter]) == .submit(true))
    }

    @Test("A confirmation steps back on escape and cancels on Ctrl-C")
    func confirmEscape() {
        var prompt = ConfirmPrompt(title: "Run it?")
        #expect(prompt.apply(.escape) == .back)
        #expect(prompt.apply(.controlD) == .cancel)
        #expect(prompt.summary(for: true) == "? Run it?  Yes")
    }

    // MARK: - Running

    @Test("The runner clears the prompt and leaves one summary line behind")
    func runnerDrawsAndSummarises() {
        var written = ""
        let runner = PromptRunner(
            reader: ScriptedKeyReader([.down, .enter]),
            width: { 40 },
            write: { written += $0 }
        )
        let outcome = runner.run(SelectPrompt(title: "Provider", items: providers))
        #expect(outcome == .submit("grok"))
        #expect(written.hasSuffix("? Provider  grok\n"))
        // Nothing but the summary survives: every frame is cleared first.
        #expect(written.contains(ProgressRenderer.clearBelow))
    }

    @Test("Input that ends without an answer reads as a cancellation")
    func runnerCancelsOnEndOfInput() {
        let runner = PromptRunner(
            reader: ScriptedKeyReader([]),
            width: { 40 },
            write: { _ in }
        )
        #expect(runner.run(ConfirmPrompt(title: "Run it?")) == .cancel)
    }
}
