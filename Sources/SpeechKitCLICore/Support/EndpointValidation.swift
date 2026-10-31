import Foundation

enum EndpointValidation {
    static func url(_ value: String, option: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw CLIError.usage("\(option) is not a valid URL.")
        }
        try validate(url, option: option)
        return url
    }

    static func validate(_ url: URL, option: String) throws {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = parts?.host?.lowercased() ?? ""
        let scheme = parts?.scheme?.lowercased()
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        let authNames: Set<String> = ["key", "api_key", "apikey", "access_token", "token", "authorization"]
        guard !host.isEmpty, parts?.user == nil, parts?.password == nil, parts?.fragment == nil,
              scheme == "https" || (scheme == "http" && loopback),
              !(parts?.queryItems ?? []).contains(where: { authNames.contains($0.name.lowercased()) }) else {
            throw CLIError.usage("\(option) requires HTTPS, or HTTP on loopback, without user info, fragments, or credentials in the query.")
        }
    }

    static func validate(endpoint: URL?, filesEndpoint: URL?, provider: CLIProvider) throws {
        if let endpoint { try validate(endpoint, option: "--endpoint") }
        if let filesEndpoint { try validate(filesEndpoint, option: "--files-endpoint") }
        guard provider == .gemini else {
            if filesEndpoint != nil { throw CLIError.usage("--files-endpoint is only supported by gemini.") }
            return
        }
        guard endpoint != nil || filesEndpoint != nil else { return }
        guard let endpoint, let filesEndpoint,
              endpoint.path.hasSuffix("/interactions"), filesEndpoint.path.hasSuffix("/files"),
              endpoint.scheme?.lowercased() == filesEndpoint.scheme?.lowercased(),
              endpoint.host?.lowercased() == filesEndpoint.host?.lowercased(),
              (endpoint.port ?? (endpoint.scheme?.lowercased() == "https" ? 443 : 80)) ==
                (filesEndpoint.port ?? (filesEndpoint.scheme?.lowercased() == "https" ? 443 : 80)) else {
            throw CLIError.usage("Gemini custom routes require --endpoint ending in /interactions and --files-endpoint ending in /files on the same origin.")
        }
    }
}
