import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("SpeechKit 3 endpoint rules")
struct EndpointValidationTests {
    @Test("Secure and loopback endpoints are accepted", arguments: [
        "https://proxy.example.com/transcribe", "http://localhost:8080/transcribe",
        "http://127.0.0.1:8080/transcribe", "http://[::1]:8080/transcribe"
    ])
    func accepted(_ endpoint: String) throws {
        #expect(try EndpointValidation.url(endpoint, option: "--endpoint").absoluteString == endpoint)
    }

    @Test("Unsafe endpoints fail without echoing their values", arguments: [
        "http://proxy.example.com/transcribe", "ws://proxy.example.com/transcribe",
        "file:///tmp/audio", "/relative", "https://user:synthetic-secret@proxy.example.com/transcribe",
        "https://proxy.example.com/transcribe?TOKEN=synthetic-secret",
        "https://proxy.example.com/transcribe#synthetic-secret"
    ])
    func rejected(_ endpoint: String) {
        let error = #expect(throws: CLIError.self) {
            _ = try EndpointValidation.url(endpoint, option: "--endpoint")
        }
        #expect(error?.exitCode == 1)
        #expect(error?.localizedDescription.contains("synthetic-secret") == false)
    }

    @Test("Gemini requires both REST routes on the same origin")
    func geminiRoutes() throws {
        let interactions = URL(string: "https://proxy.example.com/v1beta/interactions")!
        let files = URL(string: "https://proxy.example.com/upload/v1beta/files")!
        try EndpointValidation.validate(endpoint: interactions, filesEndpoint: files, provider: .gemini)
        try EndpointValidation.validate(endpoint: nil, filesEndpoint: nil, provider: .gemini)
        #expect(throws: CLIError.self) {
            try EndpointValidation.validate(endpoint: interactions, filesEndpoint: nil, provider: .gemini)
        }
        #expect(throws: CLIError.self) {
            try EndpointValidation.validate(endpoint: nil, filesEndpoint: files, provider: .gemini)
        }
        #expect(throws: CLIError.self) {
            try EndpointValidation.validate(endpoint: interactions, filesEndpoint: files, provider: .openai)
        }
        for rejected in [
            "https://other.example.com/files", "https://proxy.example.com:8443/files",
            "https://proxy.example.com/upload", "http://proxy.example.com/files"
        ] {
            #expect(throws: CLIError.self) {
                try EndpointValidation.validate(endpoint: interactions, filesEndpoint: URL(string: rejected), provider: .gemini)
            }
        }
    }

    @Test("The Files route flag parses and provider setup fails before I/O")
    func commandAndRegistry() async throws {
        let command = try Transcribe.parse([
            "test.wav", "-p", "gemini", "--endpoint", "https://proxy.example.com/interactions",
            "--files-endpoint", "https://proxy.example.com/files"
        ])
        #expect(command.transcription.filesEndpoint == "https://proxy.example.com/files")
        await #expect(throws: CLIError.self) {
            _ = try await ProviderRegistry.makeRunner(for: .gemini, context: RunContext(
                credential: .apiKey("dummy"), endpoint: URL(string: "https://proxy.example.com/interactions")
            ))
        }
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["test.wav", "-p", "openai", "--endpoint", "http://remote.example.com/upload"])
        }
    }
}
