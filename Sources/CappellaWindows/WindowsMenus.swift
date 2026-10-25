import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation
import WinSDK

extension WindowsEditor {
    func menuItem(_ title: String, shortcut: String = "", action: @escaping () -> Void) -> MenuFlyoutItem {
        let item = MenuFlyoutItem(); item.text = title
        if !shortcut.isEmpty { item.keyboardAcceleratorTextOverride = shortcut }
        item.click.addHandler { _, _ in action() }
        return item
    }
    func checkedMenuItem(_ title: String, shortcut: String = "", checked: @escaping () -> Bool,
                         action: @escaping () -> Void) -> ToggleMenuFlyoutItem {
        let item = ToggleMenuFlyoutItem(); item.text = title; item.isChecked = checked()
        if !shortcut.isEmpty { item.keyboardAcceleratorTextOverride = shortcut }
        menuChecks.append((item, checked))
        item.click.addHandler { [weak self] _, _ in action(); self?.refreshMenuChecks() }
        return item
    }
    func refreshMenuChecks() {
        for (item, checked) in menuChecks {
            let value = checked()
            if item.isChecked != value { item.isChecked = value }
        }
    }
    func savePreferences() {
        if !self.document.preferences.save() {
            Task { @MainActor [weak self] in
                await self?.showError("Impossible d'enregistrer les préférences dans " + WindowsSettings.fileURL.path)
            }
        }
    }
    func asyncItem(_ title: String, shortcut: String = "", action: @escaping @MainActor () async -> Void) -> MenuFlyoutItem {
        menuItem(title, shortcut: shortcut) { Task { @MainActor in await action() } }
    }
    func makeMenu() -> MenuBar {
        let bar = MenuBar(); bar.isTabStop = false
        func menu(_ name: String, _ items: [MenuFlyoutItemBase]) {
            let menu = MenuBarItem(); menu.title = name; menu.isTabStop = false
            for item in items { menu.items.append(item) }; bar.items.append(menu)
        }
        menu("Fichier", [
            asyncItem("Nouveau", shortcut: "Ctrl+N") { [unowned self] in await newProject() },
            asyncItem("Ouvrir…", shortcut: "Ctrl+O") { [unowned self] in if let url = await pickFile([".detx", ".cappellaproject"]) { await open(url) } },
            asyncItem("Ouvrir une sauvegarde…") { [unowned self] in if let url = await pickFile([".cappellaproject"]) { await open(url, recovery: true) } },
            MenuFlyoutSeparator(),
            asyncItem("Enregistrer", shortcut: "Ctrl+S") { [unowned self] in _ = await save() },
            asyncItem("Enregistrer sous…", shortcut: "Ctrl+Maj+S") { [unowned self] in _ = await save(as: true) },
            asyncItem("Enregistrer une copie sous…", shortcut: "Ctrl+Alt+S") { [unowned self] in _ = await save(copy: true) },
            MenuFlyoutSeparator(),
            asyncItem("Ouvrir l'image…", shortcut: "Ctrl+Maj+V") { [unowned self] in await chooseMedia(audio: false) },
            asyncItem("Propriétés…", shortcut: "Ctrl+P") { [unowned self] in await properties() },
            asyncItem("Exporter le script…", shortcut: "Ctrl+E") { [unowned self] in await exportText(crossTable: false) },
            asyncItem("Exporter le croisillé…") { [unowned self] in await exportText(crossTable: true) },
            MenuFlyoutSeparator(),
            menuItem("Quitter") { [unowned self] in try? window.close() }
        ])
        let tracks = MenuFlyoutSubItem(); tracks.text = "Piste"
        tracks.items.append(menuItem("Piste précédente", shortcut: "Ctrl+Haut") { [unowned self] in self.document.selectTrack(self.document.track - 1) })
        tracks.items.append(menuItem("Piste suivante", shortcut: "Ctrl+Bas") { [unowned self] in self.document.selectTrack(self.document.track + 1) })
        tracks.items.append(MenuFlyoutSeparator())
        for track in 0..<4 { tracks.items.append(checkedMenuItem("Piste \(track + 1)", shortcut: "F\(track + 5)", checked: { [unowned self] in self.document.track == track }) { [unowned self] in self.document.selectTrack(track) }) }
        let signs = MenuFlyoutSubItem(); signs.text = "Ajouter un signe"
        for (name, kind) in signKinds {
            signs.items.append(menuItem(name) { [unowned self] in addSign(kind) })
        }
        signs.items.append(MenuFlyoutSeparator())
        signs.items.append(menuItem("Boucle") { [unowned self] in addMarker(loop: true) })
        signs.items.append(menuItem("Changement de plan") { [unowned self] in addMarker(loop: false) })
        menu("Édition", [
            menuItem("Annuler", shortcut: "Ctrl+Z") { [unowned self] in self.document.undo() },
            menuItem("Rétablir", shortcut: "Ctrl+Y") { [unowned self] in self.document.redo() },
            MenuFlyoutSeparator(),
            menuItem("Couper", shortcut: "Ctrl+X") { [unowned self] in copyPhrase(cut: true) },
            menuItem("Copier", shortcut: "Ctrl+C") { [unowned self] in copyPhrase() },
            asyncItem("Coller", shortcut: "Ctrl+V") { [unowned self] in await pastePhrase() },
            asyncItem("Rechercher…", shortcut: "Ctrl+F") { [unowned self] in await find() },
            MenuFlyoutSeparator(), tracks, signs,
            menuItem("Supprimer le signe", shortcut: "Suppr") { [unowned self] in perform { try self.document.removeSign() } },
            menuItem("Décrocher tous les signes", shortcut: "Ctrl+Maj+D") { [unowned self] in detachSigns() },
            MenuFlyoutSeparator(),
            asyncItem("Mode Édition / Mode Détection", shortcut: "Entrée") { [unowned self] in await toggleEditing() },
            menuItem("Annuler la phrase", shortcut: "Échap") { [unowned self] in self.document.cancelEditing(); updateTextEditor() },
            menuItem("Supprimer la phrase", shortcut: "Ctrl+Suppr") { [unowned self] in perform { try self.document.deletePhrase() } },
            menuItem("Voix off", shortcut: "Ctrl+U") { [unowned self] in perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } } },
            asyncItem("Rôles…", shortcut: "Ctrl+R") { [unowned self] in await roles() },
            menuItem("Vérifier", shortcut: "F4") { [unowned self] in perform { try self.document.project.validate() }; Task { await showError("Vérification terminée.") } },
            asyncItem("Décaler la rythmo…") { [unowned self] in await shift() },
            MenuFlyoutSeparator(),
            asyncItem("Préférences…") { [unowned self] in await preferences() }
        ])
        let shuttle = MenuFlyoutSubItem(); shuttle.text = "Shuttle"
        for speed in PlaybackControls.shuttleSpeeds {
            shuttle.items.append(checkedMenuItem(speed.title, checked: { [unowned self] in media.rate == speed.rate }) {
                [unowned self] in setRate(speed.rate)
            })
        }
        var control: [MenuFlyoutItemBase] = [
            menuItem("Lecture/Pause", shortcut: "Espace") { [unowned self] in togglePlay() },
            menuItem("Lecture avant", shortcut: "Haut") { [unowned self] in setRate(media.rate == 1 ? 0 : 1) },
            menuItem("Lecture inverse", shortcut: "Bas") { [unowned self] in setRate(media.rate == -1 ? 0 : -1) },
            menuItem("Stop") { [unowned self] in media.stop() },
            MenuFlyoutSeparator(),
            menuItem("Image suivante", shortcut: "Alt+Droite") { [unowned self] in media.stop(); seek(self.document.frame + 1) },
            menuItem("Image précédente", shortcut: "Alt+Gauche") { [unowned self] in media.stop(); seek(self.document.frame - 1) },
            MenuFlyoutSeparator(),
            menuItem("Jog avant") { [unowned self] in setRate(PlaybackControls.jogSpeed) },
            menuItem("Jog arrière") { [unowned self] in setRate(-PlaybackControls.jogSpeed) },
            shuttle,
            MenuFlyoutSeparator()
        ]
        let navigation: [(String, String, String, Int)] = [
            ("Signe précédent", "Gauche", "sign", -1), ("Signe suivant", "Droite", "sign", 1),
            ("Phrase précédente", "Tab/F9", "phrase", -1), ("Phrase suivante", "Maj+Tab/F10", "phrase", 1),
            ("Phrase précédente de ce rôle", "Ctrl+F9", "role", -1), ("Phrase suivante de ce rôle", "Ctrl+F10", "role", 1),
            ("Boucle précédente", "F11", "loop", -1), ("Boucle suivante", "F12", "loop", 1),
            ("Plan précédent", "", "shot", -1), ("Plan suivant", "", "shot", 1)
        ]
        for (title, shortcut, kind, direction) in navigation {
            control.append(menuItem(title, shortcut: shortcut) { [unowned self] in navigate(kind, direction) })
        }
        control.append(MenuFlyoutSeparator())
        control.append(asyncItem("Changer le timestamp…") { [unowned self] in await changeTimestamp() })
        let orphee = menuItem("Machine Orphée…") {}
        orphee.isEnabled = false
        control.append(orphee)
        menu("Contrôle", control)
        menu("Position", [asyncItem("Aller au timecode…", shortcut: "Ctrl+G") { [unowned self] in await goTimecode() }, menuItem("Marquer cette position", shortcut: "Ctrl+D") { [unowned self] in markPosition() }])
        menu("Affichage", [
            checkedMenuItem("Détection", shortcut: "Ctrl+Alt+F9", checked: { [unowned self] in self.document.preferences.showDetection }) { [unowned self] in self.document.preferences.showDetection.toggle(); savePreferences(); refresh() },
            checkedMenuItem("Grille et signes", shortcut: "Ctrl+Alt+F10", checked: { [unowned self] in self.document.preferences.showGrid }) { [unowned self] in self.document.preferences.showGrid.toggle(); savePreferences(); refresh() },
            checkedMenuItem("Plein écran", shortcut: "Alt+Entrée", checked: { [unowned self] in videoOnly }) { [unowned self] in toggleFullScreen() },
            menuItem("Zoom avant", shortcut: "+") { [unowned self] in zoom(1.25) },
            menuItem("Zoom arrière", shortcut: "−") { [unowned self] in zoom(0.8) },
            menuItem("Écran de contrôle") { [unowned self] in showProjection() }
        ])
        menu("Audio", [
            checkedMenuItem("Basculer VO / VI", shortcut: "F2", checked: { [unowned self] in media.usingVI }) { [unowned self] in media.toggleVI(); refreshClock() },
            asyncItem("Ouvrir le son…") { [unowned self] in await chooseMedia(audio: true) },
            menuItem("Monter le volume", shortcut: "Ctrl++") { [unowned self] in media.volume = min(1, media.volume + 0.1); media.applyAudio() },
            menuItem("Baisser le volume", shortcut: "Ctrl+-") { [unowned self] in media.volume = max(0, media.volume - 0.1); media.applyAudio() },
            checkedMenuItem("Couper le son", shortcut: "Ctrl+*", checked: { [unowned self] in media.muted }) { [unowned self] in media.muted.toggle(); media.applyAudio() }
        ])
        menu("Aide", [
            menuItem("Documentation", shortcut: "F1") { [unowned self] in openWeb("https://cappella.app/") },
            menuItem("Raccourcis clavier") { [unowned self] in openWeb("https://cappella.app/documentation13.html") },
            menuItem("Rechercher des mises à jour") { [unowned self] in openWeb("https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases") },
            asyncItem("À propos de Cappella") { [unowned self] in await about() }
        ])
        return bar
    }
    var signKinds: [(String, String)] { [
        ("Début de phrase ouverte", "in_open"), ("Fin de phrase ouverte", "out_open"),
        ("Début de phrase fermée", "in_close"), ("Fin de phrase fermée", "out_close"),
        ("Labiale m, b, p", "mpb"), ("Demi-labiale f, v, r", "fvr"), ("Neutre", "neutral"),
        ("Cul de poule", "weuque"), ("Grande ouverture A", "a"), ("Ouverture en rond O", "o")
    ] }
    func togglePlay() { setRate(media.rate == 0 ? 1 : 0) }
    func setRate(_ rate: Double) {
        self.document.finishEditing(); logicalFrame = Double(self.document.frame); updateTextEditor(); perform { try media.setRate(rate) }
    }
    func navigate(_ kind: String, _ direction: Int) {
        media.stop(); if let frame = self.document.navigate(kind, direction, mediaDuration: media.duration) { seek(frame) }; updateTextEditor()
    }
    func zoom(_ factor: Double) { self.document.preferences.pixelsPerSecond = min(800, max(15, self.document.preferences.pixelsPerSecond * factor)); savePreferences(); renderBand(); updateTextEditor() }
    func addMarker(loop: Bool) {
        perform {
            try self.document.commit { project in
                ProjectEditing.addMarker(in: &project, frame: self.document.frame, loop: loop)
            }
        }
    }
    func addSign(_ kind: String) {
        if kind.hasPrefix("in_") { Task { @MainActor in await newPhrase(edit: false, kind: kind) } }
        else { perform { try self.document.addSign(kind) }; updateTextEditor() }
    }
    func detachSigns() {
        perform { try self.document.mutateCue { cue in
            ProjectEditing.detachAllSigns(in: &cue)
        } }
    }
    func contextMenu(_ args: RightTappedRoutedEventArgs?) {
        guard let args, let point = try? args.getPosition(bandContainer) else { return }
        let (cue, sign, clickedTrack, target) = hit(point)
        guard let cue else {
            let menu = MenuFlyout()
            menu.items.append(asyncItem("Coller") { [unowned self] in
                media.stop(); self.document.selectTrack(clickedTrack); seek(target)
                await pastePhrase()
            })
            try? menu.showAt(bandContainer, point); args.handled = true
            return
        }
        if self.document.editing, self.document.selection == cue.id,
           let input = textEditor, input.selectionLength > 0, sign == nil {
            let textMenu = MenuFlyout()
            textMenu.items.append(menuItem("Couper le texte") { [weak input] in try? input?.cutSelectionToClipboard() })
            textMenu.items.append(menuItem("Copier le texte") { [weak input] in try? input?.copySelectionToClipboard() })
            textMenu.items.append(menuItem("Coller du texte") { [weak input] in try? input?.pasteFromClipboard() })
            textMenu.items.append(MenuFlyoutSeparator())
            textMenu.items.append(asyncItem("Coller une phrase…") { [unowned self] in
                media.stop(); self.document.selectTrack(clickedTrack); seek(target); await pastePhrase()
            })
            try? textMenu.showAt(bandContainer, point); args.handled = true
            return
        }
        self.document.selection = cue.id; self.document.track = cue.track; self.document.signSelection = sign?.id
        let menu = MenuFlyout()
        menu.items.append(menuItem("Supprimer la phrase") { [unowned self] in perform { try self.document.deletePhrase() } })
        let tracks = MenuFlyoutSubItem(); tracks.text = "Changer de piste"
        for track in 0..<4 { tracks.items.append(menuItem("Piste \(track + 1)") { [unowned self] in perform { try self.document.moveTrack(track) } }) }
        menu.items.append(tracks)
        menu.items.append(asyncItem("Changer rôle…") { [unowned self] in if let id = await chooseRole() { perform { try self.document.mutateCue { $0.roleID = id } } } })
        menu.items.append(menuItem("Voix off") { [unowned self] in perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } } })
        menu.items.append(menuItem("Décrocher tous les signes") { [unowned self] in detachSigns() })
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(menuItem("Couper") { [unowned self] in copyPhrase(cut: true) })
        menu.items.append(menuItem("Copier") { [unowned self] in copyPhrase() })
        menu.items.append(asyncItem("Coller") { [unowned self] in
            media.stop(); self.document.selectTrack(clickedTrack); seek(target); await pastePhrase()
        })
        menu.items.append(MenuFlyoutSeparator())
        let remove = menuItem("Supprimer le signe") { [unowned self] in perform { try self.document.removeSign() } }
        remove.isEnabled = sign != nil && sign?.id != cue.anchors.first?.id && sign?.id != cue.anchors.last?.id
        menu.items.append(remove)
        let detach = menuItem("Décrocher le signe") { [unowned self] in if let id = self.document.signSelection { perform { try self.document.mutateCue { Timeline.detachSign(in: &$0, id: id) } } } }
        detach.isEnabled = remove.isEnabled; menu.items.append(detach)
        let types = MenuFlyoutSubItem(); types.text = "Changer le type"; types.isEnabled = sign != nil
        for (name, kind) in signKinds where sign?.kind.hasPrefix("in_") == true ? kind.hasPrefix("in_") : sign?.kind.hasPrefix("out_") == true ? kind.hasPrefix("out_") : !kind.hasPrefix("in_") && !kind.hasPrefix("out_") {
            types.items.append(menuItem(name) { [unowned self] in perform { try self.document.mutateCue { cue in
                if let id = self.document.signSelection { Timeline.changeSignType(in: &cue, id: id, kind: kind) }
            } } })
        }
        menu.items.append(types); try? menu.showAt(bandContainer, point); args.handled = true
    }
    func openWeb(_ url: String) { Task { _ = try? await Launcher.launchUriAsync(Uri(url)).get() } }
    func keyDown(_ args: KeyRoutedEventArgs?) {
        guard let args else { return }
        let ctrl = GetKeyState(Int32(VK_CONTROL)) < 0
        let alt = GetKeyState(Int32(VK_MENU)) < 0
        let shift = GetKeyState(Int32(VK_SHIFT)) < 0
        if handleShortcut(key: Int(args.key.rawValue), ctrl: ctrl, alt: alt, shift: shift, isRepeat: args.keyStatus.wasKeyDown) {
            args.handled = true; dismissMenus()
        }
    }
    func handleShortcut(key: Int, ctrl: Bool, alt: Bool, shift: Bool, isRepeat: Bool) -> Bool {
        guard !dialogShowing, !isClosed else { return false }
        if key == 27 && videoOnly && !ctrl && !alt {
            if !isRepeat { toggleFullScreen() }
            return true
        }
        if ctrl && !alt && !shift {
            if key == 86, hasPhraseClipboard {
                if !isRepeat { Task { await pastePhrase() } }
                return true
            }
            if [67, 88].contains(key), self.document.selectedCue != nil,
               !timelineTextHasFocus || textEditor?.selectionLength == 0 {
                if !isRepeat { copyPhrase(cut: key == 88) }
                return true
            }
        }
        // Function-key commands and deliberate Ctrl+Alt arrows are not AltGr.
        if ctrl && alt && [120, 121].contains(key) {
            if key == 120 { self.document.preferences.showDetection.toggle() }
            else { self.document.preferences.showGrid.toggle() }
            savePreferences(); refresh(); return true
        }
        if ctrl && alt && [37, 39].contains(key) {
            moveSelectedSign(key == 37 ? -1 : 1, textAnchor: true); return true
        }
        if ctrl && !alt && key == 13, let input = textEditor, timelineTextHasFocus {
            input.selectedText = "\n"; return true
        }
        if !ctrl && !alt && self.document.editing, let character = shortcutCharacter(key),
           character == "²" || character == "&" {
            jumpToTextAnchor(character == "&" ? 1 : -1); return true
        }
        if timelineTextHasFocus {
            // AltGr is reported as Ctrl+Alt on Windows. Let native text services
            // translate it, together with dead keys and text-editing shortcuts.
            if ctrl && alt { return false }
            if !ctrl && !alt && ![13, 27, 38, 40].contains(key) { return false }
            if ctrl && !alt && ([65, 67, 88, 8, 35, 36, 37, 39].contains(key) || (key == 86 && !shift)) { return false }
        }
        if ctrl {
            // Resolve +, - and * on both the main keyboard and numeric keypad.
            if !alt, let character = shortcutCharacter(key, ignoringControl: true) {
                if character == "+" { changeVolume(0.1); return true }
                if character == "-" { changeVolume(-0.1); return true }
                if character == "*" {
                    if !isRepeat { media.muted.toggle(); media.applyAudio(); refreshClock() }
                    return true
                }
            }
            switch key {
            case 78: Task { await newProject() }
            case 79: Task { if let url = await pickFile([".detx", ".cappellaproject"]) { await open(url) } }
            case 83: Task { _ = await save(as: shift, copy: alt) }
            case 90: self.document.undo()
            case 89: self.document.redo()
            case 67 where !timelineTextHasFocus: copyPhrase()
            case 88 where !timelineTextHasFocus: copyPhrase(cut: true)
            case 86 where shift: Task { await chooseMedia(audio: false) }
            case 86 where !timelineTextHasFocus: Task { await pastePhrase() }
            case 69 where !shift: Task { await exportText(crossTable: false) }
            case 37, 39: moveSelectedSign(key == 37 ? -1 : 1)
            case 98: addSign("in_close")
            case 99: addSign("out_close")
            case 107, 187: changeVolume(0.1)
            case 109, 189: changeVolume(-0.1)
            case 106: if !isRepeat { media.muted.toggle(); media.applyAudio(); refreshClock() }
            case 70: Task { await find() }
            case 71: Task { await goTimecode() }
            case 80: Task { await properties() }
            case 82: Task { await roles() }
            case 85: if !isRepeat { perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } } }
            case 38: self.document.selectTrack(self.document.track - 1)
            case 40: self.document.selectTrack(self.document.track + 1)
            case 46: perform { try self.document.deletePhrase() }
            case 68: if shift { detachSigns() } else { markPosition() }
            case 120: navigate("role", -1)
            case 121: navigate("role", 1)
            case 116...119: perform { try self.document.moveTrack(key - 116) }
            default: return false
            }
        } else {
            switch key {
            case 32:
                if !isRepeat { togglePlay() }
                return true
            case 38: if !isRepeat { setRate(media.rate == 1 ? 0 : 1) }
            case 40: if !isRepeat { setRate(media.rate == -1 ? 0 : -1) }
            case 37: if alt { media.stop(); seek(self.document.frame - 1) } else { navigate("sign", -1) }
            case 39: if alt { media.stop(); seek(self.document.frame + 1) } else { navigate("sign", 1) }
            case 13 where alt: if !isRepeat { toggleFullScreen() }
            case 13: Task { await toggleEditing() }
            case 27: self.document.cancelEditing(); updateTextEditor()
            case 112: openWeb("https://cappella.app/")
            case 113: media.toggleVI(); refreshClock()
            case 114: if !isRepeat { findNext() }
            case 115: perform { try self.document.project.validate() }
            case 116...119: self.document.selectTrack(key - 116)
            case 120: navigate("phrase", -1)
            case 121: navigate("phrase", 1)
            case 122: navigate("loop", -1)
            case 123: navigate("loop", 1)
            case 9: navigate("phrase", shift ? 1 : -1)
            case 46:
                if let cue = self.document.selectedCue, let id = self.document.signSelection,
                   let index = cue.anchors.firstIndex(where: { $0.id == id }),
                   index > 0, index < cue.anchors.count - 1 {
                    perform { try self.document.removeSign() }
                } else { perform { try self.document.deletePhrase() } }
            case 107, 187: zoom(1.25)
            case 109, 189: zoom(0.8)
            case 96: addMarker(loop: true)
            case 97: addMarker(loop: false)
            case 98: addSign("in_open")
            case 99: addSign("out_open")
            case 100: addSign("mpb")
            case 101: addSign("fvr")
            case 102: addSign("neutral")
            case 103: addSign("a")
            case 104: addSign("o")
            case 105: addSign("weuque")
            default:
                guard !alt, let character = shortcutCharacter(key) else { return false }
                switch character.lowercased() {
                case "v": if !isRepeat { setRate(media.rate == -0.75 ? 0 : -0.75) }
                case "b": if !isRepeat { setRate(media.rate == -0.25 ? 0 : -0.25) }
                case "n": if !isRepeat { setRate(media.rate == 0.25 ? 0 : 0.25) }
                case ",": if !isRepeat { setRate(media.rate == 0.75 ? 0 : 0.75) }
                default:
                    let normalized = shift ? character.uppercased() : character.lowercased()
                    guard let text = ReactionShortcuts.text(for: normalized) else { return false }
                    if !isRepeat { Task { await reaction(text) } }
                }
            }
        }
        return true
    }
}
