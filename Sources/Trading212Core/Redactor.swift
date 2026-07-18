import Foundation

/// Deterministic final-pass sanitization for diagnostics. Prefer not to put
/// secrets in a message at all; use this before exposing third-party errors.
public enum Redactor {
    public static let marker = "<redacted>"

    public static func redact(_ text: String,
                              credentials: [Trading212Credentials] = []) -> String {
        var output = text
        for credential in credentials {
            let token = Data("\(credential.key):\(credential.secret)".utf8)
                .base64EncodedString()
            let sensitiveValues = [
                credential.key,
                credential.secret,
                token,
            ]
            for value in sensitiveValues where !value.isEmpty {
                let variants = [
                    value,
                    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                ].compactMap { $0 }.filter { !$0.isEmpty }
                for variant in variants {
                    output = output.replacingOccurrences(of: variant, with: marker)
                }
            }

            // HTTP auth scheme names are case-insensitive. Redact a complete
            // header value even when a gateway changes the prefix's casing.
            output = output.replacingOccurrences(
                of: "Basic \(token)",
                with: marker,
                options: .caseInsensitive
            )
        }

        output = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let string = String(line)
                guard string.range(of: "authorization", options: .caseInsensitive) != nil else {
                    return string
                }
                if let separator = string.firstIndex(where: { $0 == ":" || $0 == "=" }) {
                    return String(string[...separator]) + " " + marker
                }
                return marker
            }
            .joined(separator: "\n")
        return output
    }
}
