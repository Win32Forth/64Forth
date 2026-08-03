//
//  ForthApplication.swift
//  64Forth
//
//  Public domain.
//
//  Custom NSApplication so editor hotkeys (⌘←/→ find, ⌘PgUp/Dn Hyper) are
//  consumed before NSTextView / menu key-equivalent handling. Required because
//  while SZ-EDITOR blocks in KEY, AppKit often delivers ⌘arrows as line-start/end
//  without reliably reaching the keyDown monitor or SwiftUI menu shortcuts.
//

#if os(macOS)
import AppKit

@objc(ForthApplication)
final class ForthApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           KernelBridge.shared.consumeEditorHotKeyIfNeeded(event) {
            return
        }
        super.sendEvent(event)
    }
}
#endif
