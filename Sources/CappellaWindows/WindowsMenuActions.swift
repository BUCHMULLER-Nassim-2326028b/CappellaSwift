import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation

extension WindowsEditor {
    var hasInternalSign: Bool {
        guard let cue = self.document.selectedCue, let id = self.document.signSelection,
              let index = cue.anchors.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0 && index < cue.anchors.count - 1
    }
    func copySelectionOrPhrase(cut: Bool = false) {
        if self.document.editing, let input = textEditor, input.selectionLength > 0 {
            if cut { try? input.cutSelectionToClipboard() } else { try? input.copySelectionToClipboard() }
            focusTimelineInput(input)
        } else { copyPhrase(cut: cut) }
    }
    func pasteSelectionOrPhrase() async {
        if hasPhraseClipboard { await pastePhrase() }
        else if self.document.editing, let input = textEditor {
            try? input.pasteFromClipboard(); focusTimelineInput(input)
        }
    }
    func selectAllTimelineText() {
        guard self.document.editing, let input = textEditor else { return }
        try? input.selectAll(); focusTimelineInput(input); refreshMenuChecks()
    }
    func refreshRecentMenu() {
        recentMenu.items.clear()
        let stored = WindowsSettings.read()["documents.recent"] as? [String] ?? []
        let paths = stored.filter { FileManager.default.fileExists(atPath: $0) }
        for path in paths {
            recentMenu.items.append(asyncItem(URL(fileURLWithPath: path).lastPathComponent) { [unowned self] in
                await open(URL(fileURLWithPath: path))
            })
        }
        if !paths.isEmpty { recentMenu.items.append(MenuFlyoutSeparator()) }
        let clear = menuItem("Effacer le menu") { [unowned self] in
            perform { try WindowsSettings.merge(["documents.recent": [String]()]) }; refreshRecentMenu()
        }
        clear.isEnabled = !paths.isEmpty; recentMenu.items.append(clear)
        recentMenu.isEnabled = !paths.isEmpty
    }
    func rememberRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        let old = WindowsSettings.read()["documents.recent"] as? [String] ?? []
        let others = old.filter { $0.caseInsensitiveCompare(path) != .orderedSame }
        do { try WindowsSettings.merge(["documents.recent": Array(([path] + others).prefix(10))]) }
        catch { status.text = error.localizedDescription }
        refreshRecentMenu()
    }
    func importRoles() async {
        guard let url = await pickFile([".detx", ".xml"]) else { return }
        do {
            let imported = try DetX.read(Data(contentsOf: url), fps: fps)
            let identity = self.document.identity
            var choices: [(Role, CheckBox)] = []
            let list = StackPanel(); list.spacing = 8
            for role in imported.roles {
                let check = CheckBox(); check.content = role.name; check.isChecked = true
                choices.append((role, check)); list.children.append(check)
            }
            let scroll = ScrollViewer(); scroll.content = list; scroll.maxHeight = 320
            let result = await dialog("Importer les rôles", content: scroll, primary: "Importer", close: "Annuler")
            guard result == .primary, identity == self.document.identity else { return }
            let selected = choices.filter { $0.1.isChecked == true }.map { $0.0 }
            try self.document.commit { project in
                ProjectEditing.mergeRoles(selected, into: &project)
                if project.metadata == nil { project.metadata = [:] }
                project.metadata?["roles-file"] = url.path
            }
        } catch { await showError(error.localizedDescription) }
    }
    func exportDetX() async {
        media.stop()
        do {
            let picker = FileSavePicker(); try attachPicker(picker)
            picker.suggestedFileName = self.document.project.title
            picker.fileTypeChoices.insert("Détection Cappella", [".detx"].toVector())
            guard let file = try await picker.pickSaveFileAsync().get() else { return }
            try self.document.save(to: URL(fileURLWithPath: file.path), copy: true)
        } catch { await showError(error.localizedDescription) }
    }
    func deletePosition() async {
        let positions = self.document.project.positions ?? []
        guard !positions.isEmpty else { return }
        let identity = self.document.identity
        let list = ListView(); list.height = 260
        for marker in positions {
            list.items.append(Timecode.format(marker.frame, fps: fps) + " - " + marker.label)
        }
        list.selectedIndex = 0
        let result = await dialog("Supprimer une position", content: list, primary: "Supprimer", close: "Annuler")
        let index = Int(list.selectedIndex)
        guard result == .primary, identity == self.document.identity, positions.indices.contains(index) else { return }
        let id = positions[index].id
        perform { try self.document.commit { project in project.positions?.removeAll { marker in marker.id == id } } }
    }
    func verifyProject() async {
        let report: String
        do { report = try ProjectVerification.report(for: self.document.project) }
        catch { report = error.localizedDescription }
        let text = label(report); text.textWrapping = .wrap; text.isTextSelectionEnabled = true
        let scroll = ScrollViewer(); scroll.content = text; scroll.maxHeight = 360
        _ = await dialog("Vérifier", content: scroll, primary: "OK")
    }
    func showKeyboardShortcuts() async {
        let text = label("Entrée : saisir ou valider la phrase\nÉchap : annuler la phrase ou quitter le plein écran vidéo\nEspace : lecture/pause ; Haut/Bas : avant/arrière\nAlt+Gauche/Droite : une image\nGauche/Droite : signe précédent/suivant\nCtrl+Gauche/Droite : déplacer le signe\nCtrl+Alt+Gauche/Droite : déplacer son accroche\nCtrl+Haut/Bas : piste précédente/suivante\nF5-F8 : piste ; Ctrl+F5-F8 : déplacer la phrase\nF9/F10 ou Tab/Maj+Tab : phrases\nCtrl+F9/F10 : phrases du rôle ; F11/F12 : boucles\nF2 : VO/VI ; F3 : recherche suivante ; F4 : vérifier\nCtrl+R : rôles ; Ctrl+F : rechercher ; Ctrl+G : timecode\nCtrl+P : propriétés ; Ctrl+D : marquer une position\nCtrl+U : voix off ; Ctrl+Suppr : supprimer la phrase\nPavé numérique 0-9 : signes\nV/B/N/virgule : lecture lente\nPlus/Moins : zoom ; Ctrl+Plus/Moins : volume\nCtrl+* : couper le son ; Alt+Entrée : plein écran vidéo")
        text.textWrapping = .wrap; text.isTextSelectionEnabled = true
        let scroll = ScrollViewer(); scroll.content = text; scroll.maxHeight = 440
        _ = await dialog("Raccourcis clavier", content: scroll, primary: "OK", contentWidth: 560)
    }
    func checkForUpdates(userInitiated: Bool = false) async {
        guard !checkingForUpdates, !isClosed else { return }
        checkingForUpdates = true; defer { checkingForUpdates = false }
        do {
            let release = try await ReleaseUpdates.latest()
            guard !isClosed, !dialogShowing, root.xamlRoot != nil else { return }
            guard let release else {
                if userInitiated { await showError("Aucune mise à jour n'est encore publiée.") }
                return
            }
            if release.isNewer {
                let result = await dialog("Une mise à jour est disponible",
                    content: label("Cappella \(release.tag_name) est disponible. Version actuelle : \(AppVersion.current)."),
                    primary: "Voir la version", close: "Plus tard")
                if result == .primary { openWeb(ReleaseUpdates.page + "/latest") }
            } else if userInitiated { await showError("Cappella est à jour. Version actuelle : \(AppVersion.current).") }
        } catch {
            if userInitiated && !isClosed && !dialogShowing { await showError("Vérification des mises à jour impossible : " + error.localizedDescription) }
        }
    }
}
