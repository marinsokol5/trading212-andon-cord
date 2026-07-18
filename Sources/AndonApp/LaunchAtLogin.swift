import OSLog
import ServiceManagement
import Trading212Core

@MainActor
enum LaunchAtLogin {
    private static let logger = Logger(
        subsystem: AppVariant.current.bundleIdentifier,
        category: "launch-at-login")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Could not change launch-at-login: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
