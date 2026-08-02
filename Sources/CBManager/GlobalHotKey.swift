import Carbon
import Foundation
import OSLog

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPressed: (() -> Void)?

    private static let hotKeyID = EventHotKeyID(signature: OSType(0x43424D47), id: 1) // CBMG
    private static let logger = Logger(subsystem: "com.cbmanager.app", category: "hotkey")

    @discardableResult
    func register(_ shortcut: HotKeyShortcut = .fallback) -> Bool {
        unregister()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == GlobalHotKey.hotKeyID.signature,
                      hotKeyID.id == GlobalHotKey.hotKeyID.id else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                manager.onPressed?()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &handlerRef
        )

        guard handlerStatus == noErr, handlerRef != nil else {
            Self.logger.error("InstallEventHandler failed status=\(handlerStatus)")
            unregister()
            return false
        }

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, hotKeyRef != nil else {
            Self.logger.error(
                "RegisterEventHotKey failed status=\(status) keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers)"
            )
            unregister()
            return false
        }

        Self.logger.notice(
            "Registered global hotkey keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers)"
        )
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
