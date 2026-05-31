import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var callback: (() -> Void)?
    private let signature: OSType = 0x5A4D5354 // 'ZMST'
    private let id: UInt32 = 1

    func register(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        unregister()
        self.callback = callback

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("ZoomShot: RegisterEventHotKey failed with status \(status)")
            return
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData = userData, let eventRef = eventRef else { return noErr }
            var receivedID = EventHotKeyID()
            let res = GetEventParameter(eventRef,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &receivedID)
            if res == noErr {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if receivedID.signature == manager.signature && receivedID.id == manager.id {
                    DispatchQueue.main.async { manager.callback?() }
                }
            }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handler { RemoveEventHandler(handler) }
        hotKeyRef = nil
        handler = nil
    }

    deinit { unregister() }
}
