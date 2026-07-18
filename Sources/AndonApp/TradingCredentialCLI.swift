import Foundation
import Trading212Core

struct CLIInvocationResult: Sendable {
    let exitCode: Int32
    let output: String

    var succeeded: Bool { exitCode == 0 }
}

struct CLICredentialStatus: Decodable, Sendable {
    let readConfigured: Bool
    let tradingConfigured: Bool
}

enum TradingCredentialCLI {
    private struct Payload: Encodable {
        let key: String
        let secret: String
    }

    // The bundled CLI shares the app's build variant, so both sides resolve
    // the same fixed environment; no environment flag exists any more.
    static func setTradingCredential(key: String, secret: String) async -> CLIInvocationResult {
        await Task.detached(priority: .userInitiated) {
            do {
                let payload = try JSONEncoder().encode(Payload(key: key, secret: secret))
                return try run(
                    arguments: ["credentials", "set-trading", "--stdin-json"],
                    stdin: payload,
                    redactions: [key, secret])
            } catch {
                return CLIInvocationResult(exitCode: 5, output: error.localizedDescription)
            }
        }.value
    }

    static func deleteTradingCredential() async -> CLIInvocationResult {
        await Task.detached(priority: .userInitiated) {
            do {
                return try run(
                    arguments: ["credentials", "delete", "--trading"],
                    stdin: nil,
                    redactions: [])
            } catch {
                return CLIInvocationResult(exitCode: 5, output: error.localizedDescription)
            }
        }.value
    }

    static func credentialStatus() async -> CLICredentialStatus? {
        await Task.detached(priority: .utility) {
            do {
                let result = try run(
                    arguments: ["credentials", "status", "--json"],
                    stdin: nil,
                    redactions: [])
                guard result.succeeded else { return nil }
                return try JSONDecoder().decode(
                    CLICredentialStatus.self,
                    from: Data(result.output.utf8))
            } catch {
                return nil
            }
        }.value
    }

    private static func run(
        arguments: [String],
        stdin: Data?,
        redactions: [String]
    ) throws -> CLIInvocationResult {
        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        if let stdin { try inputPipe.fileHandleForWriting.write(contentsOf: stdin) }
        try inputPipe.fileHandleForWriting.close()
        // Drain while the child runs so even an unexpectedly verbose diagnostic
        // cannot fill the pipe and deadlock setup.
        let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        var output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if redactions.count >= 2 {
            let credentials = Trading212Credentials(key: redactions[0], secret: redactions[1])
            output = Redactor.redact(output, credentials: [credentials])
        } else {
            output = Redactor.redact(output)
        }
        if output.isEmpty {
            output = process.terminationStatus == 0 ? "Saved." : "The CLI could not complete the request."
        }
        return CLIInvocationResult(exitCode: process.terminationStatus, output: output)
    }

    private static func executableURL() throws -> URL {
        let bundled = BundledCodeVerifier.expectedCLIURL
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            try BundledCodeVerifier.verifyCLI(at: bundled)
            return bundled
        }

        // Useful when launching the SwiftPM executable directly during development:
        // both products live beside one another in `.build/<configuration>/`.
        guard AppVariant.current == .development else { throw CLIError.notBundled }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("t212")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }

        throw CLIError.notBundled
    }

    private enum CLIError: LocalizedError {
        case notBundled

        var errorDescription: String? {
            "The verified bundled t212 command could not be found. Reinstall Trading212 Andon Cord and try again."
        }
    }
}
