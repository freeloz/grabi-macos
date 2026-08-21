import Foundation
import Carbon.HIToolbox

/// Global keyboard shortcuts via Carbon (no Accessibility permission
/// required): ⌘⇧2 record/stop · ⌘⇧P pause/resume.
final class HotkeyManager {
    var onToggleRecord: (() -> Void)?
    var onTogglePause: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                switch hotKeyID.id {
                case 1: manager.onToggleRecord?()
                case 2: manager.onTogglePause?()
                default: break
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef)

        let signature = OSType(0x47524249) // "GRBI"
        var recordRef: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: signature, id: 1),
            GetApplicationEventTarget(), 0, &recordRef)
        hotKeyRefs.append(recordRef)

        var pauseRef: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: signature, id: 2),
            GetApplicationEventTarget(), 0, &pauseRef)
        hotKeyRefs.append(pauseRef)
    }
}
