import Foundation
import CappellaCore
import UWP
import WinUI
@_spi(WinRTInternal) import WindowsFoundation

extension WindowsEditor {
    func dialog(_ title: String, content: UIElement, primary: String = "OK", secondary: String = "", close: String = "", validatePrimary: (() -> Bool)? = nil, secondaryAction: (() -> Void)? = nil, contentWidth: Double? = nil, defaultButton: ContentDialogButton = .none) async -> ContentDialogResult {
        guard !dialogShowing, !isClosed else { return .none }
        dialogShowing = true; defer { dialogShowing = false }
        let dialog = ContentDialog(); dialog.title = title; dialog.content = content
        activeDialog = dialog
        defer { if activeDialog === dialog { activeDialog = nil } }
        dialog.requestedTheme = dark ? .dark : .light
        let bodyWidth = contentWidth ?? 440
        if let text = content as? TextBlock { text.textWrapping = .wrap; text.maxWidth = bodyWidth }
        // Limit the native surface, not ContentDialog's full-root popup layer.
        _ = dialog.resources.insert("ContentDialogMaxWidth", bodyWidth + 48)
        dialog.xamlRoot = root.xamlRoot; dialog.primaryButtonText = primary
        dialog.secondaryButtonText = secondary; dialog.closeButtonText = close
        dialog.defaultButton = defaultButton
        if let validatePrimary {
            dialog.primaryButtonClick.addHandler { _, args in args?.cancel = !validatePrimary() }
        }
        if let secondaryAction {
            dialog.secondaryButtonClick.addHandler { _, args in args?.cancel = true; secondaryAction() }
        }
        do { return try await dialog.showAsync().get() } catch { status.text = error.localizedDescription; return .none }
    }

    func form(_ title: String, fields: [(String, TextBox)]) async -> Bool {
        let panel = StackPanel(); panel.spacing = 16; panel.width = 400
        for (name, field) in fields {
            field.header = name; field.minWidth = 0; field.horizontalAlignment = .stretch
            panel.children.append(field)
        }
        panel.loaded.addHandler { _, _ in
            if let first = fields.first?.1 { _ = try? first.focus(.programmatic); try? first.selectAll() }
        }
        let scroll = ScrollViewer(); scroll.content = panel
        scroll.maxHeight = min(480, max(240, root.actualHeight - 220))
        scroll.horizontalScrollBarVisibility = .disabled
        scroll.verticalScrollBarVisibility = .auto
        return await dialog(title, content: scroll, primary: "OK", close: "Annuler",
                            contentWidth: 400, defaultButton: .primary) == .primary
    }
    func dialogHint(_ text: String) -> TextBlock {
        let view = label(text, size: 12, color: ink(dark ? 0xB8B8B8 : 0x606060))
        view.textWrapping = .wrap
        return view
    }
    func dialogError() -> TextBlock {
        let view = label("", size: 12, color: ink(dark ? 0xFFB4AB : 0xB3261E))
        view.textWrapping = .wrap; view.minHeight = 18
        return view
    }
    func dialogSection(_ title: String, _ controls: [UIElement]) -> StackPanel {
        let heading = label(title, size: 14); heading.fontWeight = FontWeights.semiBold
        let panel = stack([heading] + controls, spacing: 12)
        panel.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        return panel
    }
    func chooseMedia(audio: Bool) async {
        guard let url = await pickFile(audio ? [".wav", ".aiff", ".aif", ".mp3", ".m4a", ".flac", ".mp4"] : [".mp4", ".mov", ".mkv", ".avi", ".wmv"]) else { return }
        perform {
            try self.document.commit { if audio { $0.audioPath = url.path } else { $0.videoPath = url.path } }
            try loadProjectMedia()
            media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
        }
        refresh()
    }
    func newPhrase(edit: Bool = true, kind: String = "in_open", text: String = "") async {
        media.stop()
        guard let role = await chooseRole() else { return }
        perform {
            try self.document.createPhrase(role: role, text: text, edit: edit)
            try self.document.mutateCue { cue in var signs = cue.anchors; signs[0].kind = kind; cue.signs = signs }
        }
        updateTextEditor(focus: edit)
    }
    func toggleEditing() async {
        media.stop()
        if let cue = self.document.selectedCue, cue.pendingEnd == true {
            perform {
                try self.document.commit {
                    try ProjectEditing.finalizePhrase(in: &$0, id: cue.id, frame: self.document.frame)
                }
                self.document.finishEditing()
            }
            refresh(); return
        }
        if self.document.editing { self.document.finishEditing(); refresh(); return }
        if let cue = self.document.project.cues.last(where: { $0.track == self.document.track && $0.start <= self.document.frame && $0.end >= self.document.frame }) {
            self.document.beginEditing(cue, at: self.document.frame); updateTextEditor(focus: true)
        } else { await newPhrase() }
    }
    // Fixed left-hand categories with native selection and retained draft pages.
    func dialogCategories(_ sections: [(String, UIElement)]) -> NavigationView {
        let navigation = NavigationView()
        navigation.paneDisplayMode = .left
        navigation.isPaneOpen = true; navigation.openPaneLength = 170
        navigation.isPaneToggleButtonVisible = false
        navigation.isBackButtonVisible = .collapsed
        navigation.isSettingsVisible = false; navigation.alwaysShowHeader = false
        navigation.width = min(720, max(520, root.actualWidth - 96))
        navigation.height = min(470, max(280, root.actualHeight - 220))
        var items: [NavigationViewItem] = []
        var pages: [ScrollViewer] = []
        for section in sections {
            let item = NavigationViewItem(); item.content = section.0
            navigation.menuItems.append(item); items.append(item)
            let heading = label(section.0, size: 20); heading.fontWeight = FontWeights.semiBold
            let body = stack([heading, section.1], spacing: 20)
            let page = ScrollViewer(); page.content = body
            page.horizontalScrollBarVisibility = .disabled
            page.verticalScrollBarVisibility = .auto
            page.padding = Thickness(left: 24, top: 12, right: 16, bottom: 16)
            pages.append(page)
        }
        // Keep the actual Swift projections alive in the handler. Reading their
        // native selection state avoids casting boxed IInspectable content or
        // comparing freshly projected event objects with the original wrappers.
        let content = Grid()
        for (index, page) in pages.enumerated() {
            page.visibility = index == 0 ? .visible : .collapsed
            content.children.append(page)
        }
        navigation.content = content
        navigation.selectionChanged.addHandler { _, _ in
            guard let selected = items.firstIndex(where: { $0.isSelected }) else { return }
            for (index, page) in pages.enumerated() {
                page.visibility = index == selected ? .visible : .collapsed
            }
        }
        if let first = items.first { navigation.selectedItem = first }
        return navigation
    }
    func dialogField(_ title: String, _ control: FrameworkElement) -> Grid {
        let grid = Grid(); grid.rowSpacing = 6
        for _ in 0..<2 {
            let row = RowDefinition(); row.height = GridLength(value: 0, gridUnitType: .auto)
            grid.rowDefinitions.append(row)
        }
        let text = label(title, size: 14); text.textWrapping = .wrap
        control.minWidth = 0; control.horizontalAlignment = .stretch
        grid.children.append(text); try? Grid.setRow(control, 1); grid.children.append(control)
        return grid
    }
    func dialogColumns(_ controls: [FrameworkElement]) -> Grid {
        let grid = Grid(); grid.columnSpacing = 16; grid.rowSpacing = 16
        for _ in 0..<2 {
            let column = ColumnDefinition(); column.width = GridLength(value: 1, gridUnitType: .star)
            grid.columnDefinitions.append(column)
        }
        for _ in 0..<((controls.count + 1) / 2) {
            let row = RowDefinition(); row.height = GridLength(value: 0, gridUnitType: .auto)
            grid.rowDefinitions.append(row)
        }
        for (index, control) in controls.enumerated() {
            try? Grid.setRow(control, Int32(index / 2)); try? Grid.setColumn(control, Int32(index % 2))
            grid.children.append(control)
        }
        return grid
    }
    func goTimecode() async {
        let input = textField(Timecode.format(self.document.frame, fps: fps))
        if await form("Aller au timecode", fields: [("HH:MM:SS:II", input)]) {
            guard let frame = Timecode.parse(input.text, fps: fps) else { await showError("Timecode invalide."); return }
            media.stop(); seek(frame)
        }
    }
    func shift() async {
        let input = textField("0")
        if await form("Décaler la rythmo", fields: [("Décalage en images (+ ou −)", input)]), let delta = Int(input.text) {
            perform { try self.document.commit { try $0.shift(by: delta) } }
        }
    }
    func markPosition() {
        perform { try self.document.commit { let count = $0.positions?.count ?? 0; if $0.positions == nil { $0.positions = [] }; $0.positions?.append(Marker(frame: self.document.frame, label: "Position \(count + 1)")) } }
    }
    private func clipboardString(_ value: Any?) throws -> String {
        if let text = value as? String { return text }
        // Swift/WinRT boxes native strings as IInspectable on this code path.
        // A direct "as? String" silently discarded the copied phrase.
        if let boxed = value as? WindowsFoundation.IInspectable {
            let property: __ABI_Windows_Foundation.IPropertyValue = try boxed.QueryInterface()
            return try property.GetString()
        }
        throw ProjectError.invalid("Le presse-papiers ne contient pas une phrase Cappella valide.")
    }
    var hasPhraseClipboard: Bool {
        guard let content = try? Clipboard.getContent() else { return false }
        return (try? content.contains(ProjectEditing.phraseClipboardType)) == true ||
            (try? content.contains("org.cappella-rewrite.phrase")) == true
    }
    func copyPhrase(cut: Bool = false) {
        guard let cue = self.document.selectedCue else { return }
        do {
            let data = try JSONEncoder().encode(cue)
            let package = DataPackage()
            try package.setText(cue.text)
            try package.setData(ProjectEditing.phraseClipboardType, data.base64EncodedString())
            try Clipboard.setContent(package)
            // Keep the copy usable after this instance exits. A flush failure
            // does not invalidate the in-process clipboard or delete a phrase.
            try? Clipboard.flush()
            if cut { perform { try self.document.deletePhrase() } }
        } catch { Task { await showError(error.localizedDescription) } }
    }
    func pastePhrase() async {
        guard !dialogShowing, !isClosed, !phrasePasteActive else { return }
        phrasePasteActive = true; defer { phrasePasteActive = false }
        media.stop()
        self.document.finishEditing(); updateTextEditor()
        let frame = self.document.frame, track = self.document.track, identity = self.document.identity
        do {
            guard let clipboard = try Clipboard.getContent() else { return }
            let types = [ProjectEditing.phraseClipboardType, "org.cappella-rewrite.phrase"]
            guard let type = types.first(where: { (try? clipboard.contains($0)) == true }) else { return }
            let value = try await clipboard.getDataAsync(type).get()
            let text = try clipboardString(value)
            guard let data = Data(base64Encoded: text) else { throw ProjectError.invalid("La phrase copiée est illisible.") }
            let cue = try JSONDecoder().decode(Cue.self, from: data)
            guard !isClosed, self.document.identity == identity else { return }
            try ProjectEditing.validatePaste(cue, in: self.document.project, frame: frame, track: track)
            guard let role = await chooseRole(preferred: cue.roleID), !isClosed, self.document.identity == identity else { return }
            var pasted: Cue?
            try self.document.commit {
                pasted = try ProjectEditing.paste(cue, into: &$0, frame: frame, track: track, roleID: role)
            }
            self.document.track = track; self.document.selection = pasted?.id
            self.document.signSelection = nil; refresh()
        } catch { await showError(error.localizedDescription) }
    }
    func exportText(crossTable: Bool) async {
        do {
            let picker = FileSavePicker(); try attachPicker(picker)
            picker.suggestedFileName = self.document.project.title
            picker.fileTypeChoices.insert(crossTable ? "Croisillé CSV" : "Script texte", [crossTable ? ".csv" : ".txt"].toVector())
            guard let file = try await picker.pickSaveFileAsync().get() else { return }
            let text = crossTable ? self.document.project.crossTableCSV() : self.document.project.scriptText()
            try text.write(to: URL(fileURLWithPath: file.path), atomically: true, encoding: .utf8)
        } catch { await showError(error.localizedDescription) }
    }
    func showProjection() {
        if let projection { try? projection.activate(); return }
        let projection = Window(); projection.title = "Cappella - Écran de contrôle"
        let video = MediaPlayerElement(); video.areTransportControlsEnabled = false
        try? video.setMediaPlayer(media.video); projection.content = video
        projection.closed.addHandler { [weak self] _, _ in self?.projection = nil; self?.projectionVideo = nil }
        self.projection = projection; projectionVideo = video; try? projection.activate()
    }
    func about() async {
        let logo = Image(); logo.width = 176; logo.height = 132; logo.stretch = .uniform
        logo.horizontalAlignment = .center
        let path = resources.appendingPathComponent(dark ? "CappellaLogo_dark.png" : "CappellaLogo.png")
        if FileManager.default.fileExists(atPath: path.path) { logo.source = BitmapImage(Uri(path.absoluteString)) }
        let title = label("Cappella", size: 26); title.fontWeight = FontWeights.semiBold
        let version = dialogHint("Version \(AppVersion.current)"), author = dialogHint("Réécriture : nvssgoat")
        let original = dialogHint("Logiciel d'origine développé par Chinkel.")
        for text in [title, version, original, author] { text.textAlignment = .center; text.horizontalAlignment = .center }
        let content = stack([logo, title, version, original, author], spacing: 12); content.width = 360
        _ = await dialog("À propos de Cappella", content: content, primary: "OK",
                         contentWidth: 360, defaultButton: .primary)
    }
}
