import Darwin
import Foundation

@main
enum AndonMain {
    static func main() async {
        do {
            let cli = try AndonCLI()
            let code = await cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
            Darwin.exit(code.rawValue)
        } catch {
            FileHandle.standardError.write(Data("t212: could not initialize local workspace\n".utf8))
            Darwin.exit(1)
        }
    }
}
