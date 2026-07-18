import AppKit

// `--screenshots` renders every route to PNGs and exits before any app UI.
ScreenshotHarness.runIfRequested()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
