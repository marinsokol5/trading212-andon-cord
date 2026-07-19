import Foundation

public enum AndonExitCode: Int32, Equatable, Sendable {
    case success = 0
    case failure = 1
    case usage = 2
    case missingCredentials = 3
    case authenticationOrAccountMismatch = 4
    case networkOrAPI = 5
    case aborted = 6
    case ambiguousOrder = 7
}

public struct AndonInvocation: Equatable, Sendable {
    public enum Command: Equatable, Sendable {
        case help
        case version
        case account(json: Bool)
        case portfolio(json: Bool, output: URL?)
        case snapshotView(input: URL, json: Bool)
        case credentialsSetTrading
        case credentialsStatus(json: Bool)
        case credentialsDeleteTrading
        case sellAll(output: URL?, dryRun: Bool)
        case buyAll(input: URL, options: BuyPlanningOptions, dryRun: Bool)
    }

    public let command: Command

    public init(command: Command) {
        self.command = command
    }
}

public enum AndonArgumentError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownFlag(String)
    case missingFlagValue(String)
    case invalidDecimal(flag: String, value: String)
    case invalidInteger(flag: String, value: String)
    case invalidCombination(String)
    case missingRequiredFlag(String)

    public var description: String {
        switch self {
        case .missingCommand: "missing command"
        case .unknownCommand(let value): "unknown command: \(value)"
        case .unknownFlag(let value): "unknown flag: \(value)"
        case .missingFlagValue(let value): "flag \(value) requires a value"
        case .invalidDecimal(let flag, let value): "flag \(flag) requires a decimal, got \"\(value)\""
        case .invalidInteger(let flag, let value): "flag \(flag) requires an integer, got \"\(value)\""
        case .invalidCombination(let message): message
        case .missingRequiredFlag(let value): "missing required flag \(value)"
        }
    }
}

public enum AndonArgumentParser {
    public static func parse(_ arguments: [String]) throws -> AndonInvocation {
        var positionals: [String] = []
        var json = false
        var dryRun = false
        var help = false
        var version = false
        var output: String?
        var input: String?
        var cashFraction: Decimal?
        var minimumOrder: Decimal?
        var precision: Int?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let split = splitFlag(argument)
            let flag = split.name

            func value() throws -> String {
                if let inline = split.value { return inline }
                let next = index + 1
                guard next < arguments.count else {
                    throw AndonArgumentError.missingFlagValue(flag)
                }
                index = next
                return arguments[next]
            }

            switch flag {
            case "--json": json = true
            case "--dry-run": dryRun = true
            case "--help", "-h": help = true
            case "--version", "-V": version = true
            case "--output": output = try value()
            case "--input": input = try value()
            case "--cash-fraction":
                let raw = try value()
                guard let parsed = decimal(raw) else {
                    throw AndonArgumentError.invalidDecimal(flag: flag, value: raw)
                }
                cashFraction = parsed
            case "--min-order":
                let raw = try value()
                guard let parsed = decimal(raw) else {
                    throw AndonArgumentError.invalidDecimal(flag: flag, value: raw)
                }
                minimumOrder = parsed
            case "--precision":
                let raw = try value()
                guard let parsed = Int(raw) else {
                    throw AndonArgumentError.invalidInteger(flag: flag, value: raw)
                }
                precision = parsed
            default:
                if argument.hasPrefix("-") {
                    throw AndonArgumentError.unknownFlag(argument)
                }
                positionals.append(argument)
            }
            index += 1
        }

        if version {
            guard positionals.isEmpty else {
                throw AndonArgumentError.invalidCombination("--version cannot be combined with a command")
            }
            return AndonInvocation(command: .version)
        }
        if help || positionals.isEmpty {
            return AndonInvocation(command: .help)
        }

        let command: AndonInvocation.Command
        switch positionals {
        case ["account"]:
            try rejectMutationFlags(dryRun: dryRun)
            try rejectUnused(output: output, input: input,
                             cashFraction: cashFraction, minimumOrder: minimumOrder, precision: precision)
            command = .account(json: json)

        case ["portfolio"]:
            try rejectMutationFlags(dryRun: dryRun)
            guard input == nil else {
                throw AndonArgumentError.invalidCombination("portfolio uses --output, not --input")
            }
            guard !(json && output != nil) else {
                throw AndonArgumentError.invalidCombination("use either --json or --output, not both")
            }
            try rejectUnused(output: nil, input: nil,
                             cashFraction: cashFraction, minimumOrder: minimumOrder, precision: precision)
            command = .portfolio(json: json, output: output.map(fileURL))

        case ["snapshot", "view"]:
            try rejectMutationFlags(dryRun: dryRun)
            guard output == nil else {
                throw AndonArgumentError.invalidCombination("snapshot view uses --input, not --output")
            }
            guard let input else { throw AndonArgumentError.missingRequiredFlag("--input FILE") }
            try rejectUnused(output: nil, input: nil,
                             cashFraction: cashFraction, minimumOrder: minimumOrder, precision: precision)
            command = .snapshotView(input: fileURL(input), json: json)

        case ["credentials", "set-trading"]:
            guard !json, !dryRun, output == nil, input == nil,
                  cashFraction == nil, minimumOrder == nil, precision == nil else {
                throw AndonArgumentError.invalidCombination("unsupported flag for credentials set-trading")
            }
            command = .credentialsSetTrading

        case ["credentials", "status"]:
            guard !dryRun, output == nil, input == nil,
                  cashFraction == nil, minimumOrder == nil, precision == nil else {
                throw AndonArgumentError.invalidCombination("unsupported flag for credentials status")
            }
            command = .credentialsStatus(json: json)

        case ["credentials", "delete"]:
            guard !json, !dryRun, output == nil, input == nil,
                  cashFraction == nil, minimumOrder == nil, precision == nil else {
                throw AndonArgumentError.invalidCombination("unsupported flag for credentials delete")
            }
            command = .credentialsDeleteTrading

        case ["sell-all"]:
            guard !json, input == nil,
                  cashFraction == nil, minimumOrder == nil, precision == nil else {
                throw AndonArgumentError.invalidCombination("unsupported flag for sell-all")
            }
            command = .sellAll(output: output.map(fileURL), dryRun: dryRun)

        case ["buy-all"]:
            guard !json, output == nil else {
                throw AndonArgumentError.invalidCombination("unsupported flag for buy-all")
            }
            guard let input else { throw AndonArgumentError.missingRequiredFlag("--input FILE") }
            let options = BuyPlanningOptions(
                cashFraction: cashFraction ?? BuyPlanningOptions.default.cashFraction,
                minimumOrderValue: minimumOrder ?? BuyPlanningOptions.default.minimumOrderValue,
                quantityPrecision: precision ?? BuyPlanningOptions.default.quantityPrecision
            )
            do { try options.validate() }
            catch { throw AndonArgumentError.invalidCombination(String(describing: error)) }
            command = .buyAll(input: fileURL(input), options: options, dryRun: dryRun)

        default:
            throw AndonArgumentError.unknownCommand(positionals.joined(separator: " "))
        }

        return AndonInvocation(command: command)
    }

    private static func splitFlag(_ argument: String) -> (name: String, value: String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else {
            return (argument, nil)
        }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }

    private static func decimal(_ string: String) -> Decimal? {
        guard !string.isEmpty,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
              NSDecimalNumber(decimal: value) != .notANumber else {
            return nil
        }
        return value
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private static func rejectMutationFlags(dryRun: Bool) throws {
        guard !dryRun else {
            throw AndonArgumentError.invalidCombination("--dry-run applies only to trading commands")
        }
    }

    private static func rejectUnused(
        output: String?,
        input: String?,
        cashFraction: Decimal?,
        minimumOrder: Decimal?,
        precision: Int?
    ) throws {
        guard output == nil, input == nil,
              cashFraction == nil, minimumOrder == nil, precision == nil else {
            throw AndonArgumentError.invalidCombination("one or more flags do not apply to this command")
        }
    }
}
