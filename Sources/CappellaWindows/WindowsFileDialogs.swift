import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation
import CWindowsInterop

extension WindowsEditor {
    func mayReplace() async -> Bool {
        guard self.document.dirty else { return true }
        let result = await dialog("Enregistrer les modifications ?", content: label("Les modifications du projet courant seront perdues sans enregistrement."), primary: "Enregistrer", secondary: "Ne pas enregistrer", close: "Annuler")
        if result == .primary { return await save() }
        return result == .secondary
    }
    func attachPicker(_ picker: WinRTClass) throws {
        var stage: Int32 = 0
        let result = cappella_attach_picker(
            UnsafeMutableRawPointer(picker.thisPtr.pUnk.borrow), window.appWindow.id.value, &stage)
        guard result >= 0 else {
            let code = String(format: "0x%08X", UInt32(bitPattern: result))
            throw NSError(domain: "CappellaPicker", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: "Sélecteur Windows : échec du rattachement (étape \(stage), \(code))."
            ])
        }
    }
    func pickFile(_ extensions: [String], onError: ((String) -> Void)? = nil) async -> URL? {
        media.stop()
        do {
            let picker = FileOpenPicker(); for ext in extensions { picker.fileTypeFilter.append(ext) }; try attachPicker(picker)
            guard let file = try await picker.pickSingleFileAsync().get() else { return nil }
            return URL(fileURLWithPath: file.path)
        } catch {
            if let onError { onError(error.localizedDescription) }
            else { await showError(error.localizedDescription) }
            return nil
        }
    }
    func open(_ url: URL, recovery: Bool = false) async {
        if !recovery && self.document.url?.standardizedFileURL == url.standardizedFileURL { try? window.activate(); return }
        do {
            let project = try self.document.read(url)
            guard await mayReplace() else { return }
            unloadProjectMedia()
            self.document.replace(with: project, url: recovery ? nil : url)
            try loadProjectMedia()
            media.seek(Double(self.document.frame - project.mediaStartFrame) / Double(fps))
            if !recovery { rememberRecent(url) }
            refresh(); try window.activate()
        } catch { await showError(error.localizedDescription) }
    }
    func save(as saveAs: Bool = false, copy: Bool = false) async -> Bool {
        do {
            var destination = !saveAs && !copy ? self.document.url : nil
            if destination == nil {
                let picker = FileSavePicker()
                picker.fileTypeChoices.insert("Détection Cappella", [".detx"].toVector())
                picker.fileTypeChoices.insert("Projet Cappella", [".cappellaproject"].toVector())
                let name = self.document.url?.deletingPathExtension().lastPathComponent ?? self.document.project.title
                picker.suggestedFileName = copy ? self.document.preferences.copyName(for: name) : name
                try attachPicker(picker)
                if let file = try await picker.pickSaveFileAsync().get() { destination = URL(fileURLWithPath: file.path) }
            }
            guard let destination else { return false }
            try self.document.save(to: destination, copy: copy)
            if !copy { rememberRecent(destination) }
            return true
        } catch { await showError(error.localizedDescription); return false }
    }
}
