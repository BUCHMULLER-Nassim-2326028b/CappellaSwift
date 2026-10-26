import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import WinSDK

extension WindowsEditor {
    func toggleFullScreen() {
        if readingMode { readingMode = false; applyReadingLayout?(false) }
        if isResizing { endResize() }
        self.document.finishEditing(); updateTextEditor()
        videoOnly.toggle()
        if videoOnly { bandMotion.stop() }
        applyVideoOnlyLayout?(videoOnly)
        refresh()
    }
    func changeVolume(_ delta: Double) {
        media.volume = min(1, max(0, media.volume + delta)); media.applyAudio(); refreshClock()
    }
    func moveSelectedSign(_ delta: Int, textAnchor: Bool = false) {
        guard let id = self.document.signSelection else { return }
        perform {
            try self.document.mutateCue { cue in
                var signs = cue.anchors
                guard let index = signs.firstIndex(where: { $0.id == id }) else { return }
                if textAnchor {
                    Timeline.shiftTextAnchor(in: &cue, id: id, by: delta)
                } else { Timeline.moveSign(in: &cue, id: id, to: signs[index].frame + delta) }
            }
        }
        updateTextEditor()
    }
    func jumpToTextAnchor(_ direction: Int) {
        guard let cue = self.document.selectedCue else { return }
        let signs = cue.anchors
        let next = direction > 0
            ? signs.first(where: { $0.textOffset > self.document.caret })
            : signs.last(where: { $0.textOffset < self.document.caret })
        guard let next else { return }
        self.document.caret = next.textOffset; self.document.signSelection = next.id
        media.stop(); seek(next.frame); updateTextEditor(focus: true)
    }
    func reaction(_ text: String) async {
        if !self.document.preferences.closeReactions,
           let id = pendingReaction, self.document.selection == id,
           self.document.selectedCue?.text == text {
            perform { try self.document.addSign("out_open") }
            pendingReaction = nil; updateTextEditor()
        } else {
            await newPhrase(edit: false, text: text)
            if self.document.selectedCue?.text == text {
                pendingReaction = self.document.preferences.closeReactions ? nil : self.document.selection
                if self.document.preferences.closeReactions {
                    if let cue = self.document.selectedCue {
                        perform { try self.document.commit { try ProjectEditing.finalizePhrase(in: &$0, id: cue.id, frame: cue.end) } }
                    }
                    self.document.finishEditing(); refresh()
                }
            }
        }
    }
    /// Translate through the active keyboard layout, without consuming dead keys.
    func shortcutCharacter(_ key: Int, ignoringControl: Bool = false) -> String? {
        var state = [BYTE](repeating: 0, count: 256)
        guard state.withUnsafeMutableBufferPointer({ GetKeyboardState($0.baseAddress!) }) else { return nil }
        if ignoringControl {
            for code in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] { state[Int(code)] = 0 }
        }
        var characters = [WCHAR](repeating: 0, count: 8)
        let count = state.withUnsafeBufferPointer { keys in
            characters.withUnsafeMutableBufferPointer { buffer in
                ToUnicodeEx(UInt32(key), MapVirtualKeyW(UInt32(key), UINT(MAPVK_VK_TO_VSC)),
                    keys.baseAddress!, buffer.baseAddress!, Int32(buffer.count), 4, GetKeyboardLayout(0))
            }
        }
        guard count > 0 else { return nil }
        return String(decoding: characters.prefix(Int(count)), as: UTF16.self)
    }
}
