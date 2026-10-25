import Foundation
import WinUI
import WinAppSDK
import WindowsFoundation
import UWP
import WinSDK

extension WindowsEditor {
    func recordSmokeState() {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_SMOKE_MARKER"] else { return }
        let timer = DispatcherTimer(); timer.interval = TimeSpan(duration: 10_000_000)
        var testFrame: Int?
        timer.tick.addHandler { [weak self, timer] _, _ in
            guard let self else { return }
            var editingWorks = true
            if let cue = self.document.project.cues.first {
                if testFrame == nil {
                    testFrame = self.document.frame
                    self.document.beginEditing(cue, at: cue.start)
                    updateTextEditor(focus: true)
                    textEditor?.text = "Vérification é🙂 - saisie sur la bande."
                    return // TextChanged is delivered asynchronously by WinUI.
                }
                editingWorks = self.document.selectedCue?.text == "Vérification é🙂 - saisie sur la bande." && textEditor != nil && self.document.frame == testFrame
                self.document.cancelEditing(); updateTextEditor()
            }
            try? timer.stop()
            let state: [String: Any] = ["visible": window.visible, "title": self.document.project.title,
                "cues": self.document.project.cues.count, "pid": ProcessInfo.processInfo.processIdentifier,
                "layoutWidth": root.actualWidth, "bandElements": band.children.size + bandBackdrop.children.size, "scriptRows": scriptRows.count, "editingWorks": editingWorks]
            do { try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: path), options: .atomic) }
            catch { print(error) }
        }
        try? timer.start()
    }
}

enum WindowsActivation {
    static func trace(_ message: String) {
        guard let marker = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_ACTIVATION_MARKER"] else { return }
        let path = marker + "." + String(ProcessInfo.processInfo.processIdentifier) + ".log"
        let data = Data((message + "\n").utf8)
        if let file = FileHandle(forWritingAtPath: path) {
            defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
        } else { try? data.write(to: URL(fileURLWithPath: path)) }
    }
    static func files(in commandLine: String) -> [URL] {
        var count: Int32 = 0
        let arguments = commandLine.withCString(encodedAs: UTF16.self) { CommandLineToArgvW($0, &count) }
        guard let arguments else { return [] }
        defer { _ = LocalFree(arguments) }
        return (0..<Int(count)).compactMap { index in
            guard let argument = arguments[index] else { return nil }
            let path = String(decodingCString: argument, as: UTF16.self)
            let url = URL(fileURLWithPath: path)
            return ["detx", "cappellaproject"].contains(url.pathExtension.lowercased()) ? url : nil
        }
    }
}
