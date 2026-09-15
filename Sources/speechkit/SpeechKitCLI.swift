import SpeechKitCLICore

/// The `speechkit` executable entry point.
///
/// All behaviour lives in `SpeechKitCLICore` so the tests can import it.
@main
struct SpeechKitCLI {
    static func main() async {
        await SpeechKitCommand.runMain()
    }
}
