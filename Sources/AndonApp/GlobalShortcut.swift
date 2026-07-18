import AppKit
import Carbon
import SwiftUI

/// A Carbon hot key works globally without Accessibility permission and consumes
/// only the exact registered chord.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: () -> Void

    init(shortcut: ShortcutDefinition, action: @escaping () -> Void) {
        self.action = action
        installHandler()
        register(shortcut)
    }

    func update(_ shortcut: ShortcutDefinition) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        register(shortcut)
    }

    private func register(_ shortcut: ShortcutDefinition) {
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey)
    }

    private func installHandler() {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased))
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.callback,
            1,
            &event,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
    }

    private static let signature: OSType = 0x414E444E // "ANDN"

    private static let callback: EventHandlerUPP = { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier)
        guard status == noErr, identifier.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }
        let center = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { center.action() }
        return noErr
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: ShortcutDefinition

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = { shortcut = $0 }
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        view.onChange = { shortcut = $0 }
        view.shortcut = shortcut
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onChange: ((ShortcutDefinition) -> Void)?
    var shortcut: ShortcutDefinition = .defaultPrivacy { didSet { refreshTitle() } }
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { // Escape cancels.
            _ = window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control, .shift]).isEmpty else {
            NSSound.beep()
            return
        }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let updated = ShortcutDefinition(keyCode: UInt32(event.keyCode), modifiers: carbon)
        shortcut = updated
        onChange?(updated)
        _ = window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        guard !isRecording else { return }
        title = ShortcutName.string(shortcut)
    }
}

enum ShortcutName {
    static func string(_ shortcut: ShortcutDefinition) -> String {
        var value = ""
        if shortcut.modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += keyName(shortcut.keyCode)
        return value
    }

    private static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E",
            15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
        ]
        return names[code] ?? "Key \(code)"
    }
}
