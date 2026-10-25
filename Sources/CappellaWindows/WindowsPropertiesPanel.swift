import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func properties() async {
        media.stop()
        var draft = self.document.project
        let title = textField(draft.title), author = textField(draft.author)
        let video = textField(draft.videoPath ?? ""), sound = textField(draft.audioPath ?? "")
        let rolesFile = textField(draft.metadata?["roles-file"] ?? ""); rolesFile.isReadOnly = true
        let stamp = textField(Timecode.format(draft.mediaStartFrame, fps: fps))
        let errorText = dialogError()
        var metadataFields: [(String, TextBox)] = []
        func metadataField(_ name: String, _ key: String) -> Grid {
            let field = textField(draft.metadata?[key] ?? "")
            metadataFields.append((key, field))
            return dialogField(name, field)
        }
        func browseRow(_ name: String, _ field: TextBox, kind: Int) -> Grid {
            let browse = button("Parcourir…") { [unowned self] in
                Task { @MainActor in
                    let extensions = kind == 0 ? [".mp4", ".mov", ".mkv", ".avi", ".wmv"] :
                        kind == 1 ? [".wav", ".aiff", ".aif", ".mp3", ".m4a", ".flac", ".mp4"] : [".detx", ".xml"]
                    guard let url = await self.pickFile(extensions, onError: { errorText.text = $0 }) else { return }
                    do {
                        if kind == 2 {
                            let imported = try DetX.read(Data(contentsOf: url), fps: draft.framesPerSecond)
                            ProjectEditing.mergeRoles(imported.roles, into: &draft)
                        }
                        field.text = url.path; errorText.text = ""
                    } catch { errorText.text = error.localizedDescription }
                }
            }
            let grid = Grid(); grid.columnSpacing = 10
            let pathColumn = ColumnDefinition(); pathColumn.width = GridLength(value: 1, gridUnitType: .star)
            let browseColumn = ColumnDefinition(); browseColumn.width = GridLength(value: 0, gridUnitType: .auto)
            grid.columnDefinitions.append(pathColumn); grid.columnDefinitions.append(browseColumn)
            field.minWidth = 0; browse.verticalAlignment = .bottom
            grid.children.append(field); try? Grid.setColumn(browse, 1); grid.children.append(browse)
            return dialogField(name, grid)
        }
        let files = stack([
            dialogHint("Associez les médias et importez une liste de rôles. Le son séparé remplace celui de la vidéo."),
            browseRow("Image", video, kind: 0), browseRow("Son", sound, kind: 1),
            browseRow("Liste des rôles", rolesFile, kind: 2)
        ], spacing: 20)
        let cadence = ComboBox()
        for rate in [24, 25, 30] { cadence.items.append("\(rate) i/s") }
        cadence.selectedIndex = Int32([24, 25, 30].firstIndex(of: fps) ?? 1)
        cadence.isEnabled = draft.cues.isEmpty && draft.originalDetX == nil
        let programme = stack([
            dialogSection("Titres", [
                dialogField("Titre original", title), metadataField("Titre français", "title2"),
                dialogColumns([metadataField("Épisode", "episode.number"), metadataField("Saison", "episode.season")]),
                metadataField("Titre de l'épisode", "episode.title"),
                metadataField("Titre français de l'épisode", "episode.title2")
            ]),
            dialogSection("Écriture et détection", [
                dialogField("Auteur", author),
                dialogColumns([metadataField("Second auteur - prénom", "second-author.firstname"), metadataField("Second auteur - nom", "second-author.name")]),
                dialogColumns([metadataField("Détecteur - prénom", "detector.firstname"), metadataField("Détecteur - nom", "detector.name")])
            ]),
            dialogSection("Image", [dialogColumns([dialogField("Cadence", cadence), dialogField("Timestamp de l'image", stamp)])])
        ], spacing: 20)
        let production = stack([
            dialogColumns([metadataField("Année", "production.year"), metadataField("Pays", "production.country")]),
            metadataField("Réalisateur", "production.director"), metadataField("Producteur", "production.producer"),
            metadataField("Distributeur", "production.distributor"), metadataField("Diffuseur", "production.diffuser"),
            metadataField("Acteurs principaux", "production.actors")
        ], spacing: 16)
        let summary = textField(draft.metadata?["summary"] ?? "")
        let notes = textField(draft.metadata?["notes"] ?? "")
        for field in [summary, notes] { field.acceptsReturn = true; field.textWrapping = .wrap; field.height = 140 }
        metadataFields.append(("summary", summary)); metadataFields.append(("notes", notes))
        let description = stack([dialogField("Résumé", summary), dialogField("Notes", notes)], spacing: 20)
        var markerFields: [(UUID, TextBox, TextBox)] = []
        var removedMarkers = Set<UUID>()
        func markers(_ name: String, _ markers: [Marker]) -> StackPanel {
            let panel = dialogSection(name, [])
            if markers.isEmpty { panel.children.append(dialogHint("Aucun repère.")) }
            for marker in markers {
                let number = textField(marker.label, placeholder: "N°"); number.width = 64
                let time = textField(Timecode.format(marker.frame, fps: fps)); time.width = 145
                let line = row([number, time])
                line.children.append(button("Supprimer") { [weak line] in
                    removedMarkers.insert(marker.id); line?.visibility = .collapsed
                })
                markerFields.append((marker.id, number, time)); panel.children.append(line)
            }
            return panel
        }
        let references = stack([markers("Boucles", draft.loops), markers("Changements de plan", draft.shots)], spacing: 20)
        let categories = dialogCategories([("Fichier", files), ("Programme", programme), ("Production", production),
                               ("Description", description), ("Repères", references)])
        func apply() -> Bool {
            do {
                var next = draft
                let rates = [24, 25, 30], rateIndex = Int(cadence.selectedIndex)
                guard rates.indices.contains(rateIndex) else { throw ProjectError.invalid("Cadence invalide.") }
                next.framesPerSecond = rates[rateIndex]
                guard let origin = Timecode.parse(stamp.text, fps: next.framesPerSecond) else {
                    throw ProjectError.invalid("Timestamp de l'image invalide.")
                }
                next.title = title.text; next.author = author.text
                next.videoPath = video.text.isEmpty ? nil : video.text
                next.audioPath = sound.text.isEmpty ? nil : sound.text
                if next.metadata == nil { next.metadata = [:] }
                next.metadata?["roles-file"] = rolesFile.text
                for (key, field) in metadataFields { next.metadata?[key] = field.text }
                next.loops.removeAll { removedMarkers.contains($0.id) }
                next.shots.removeAll { removedMarkers.contains($0.id) }
                for (id, number, time) in markerFields where !removedMarkers.contains(id) {
                    guard let frame = Timecode.parse(time.text, fps: next.framesPerSecond) else {
                        throw ProjectError.invalid("Timecode invalide pour le repère « \(number.text) ».")
                    }
                    if let index = next.loops.firstIndex(where: { $0.id == id }) {
                        next.loops[index].label = number.text; next.loops[index].frame = frame
                    } else if let index = next.shots.firstIndex(where: { $0.id == id }) {
                        next.shots[index].label = number.text; next.shots[index].frame = frame
                    }
                }
                let delta = origin - next.mediaStartFrame
                if delta != 0 { try next.shift(by: delta, includingMediaOrigin: true) }
                let previous = self.document.project
                try self.document.commit { $0 = next }
                draft = next; errorText.text = ""
                for (id, _, time) in markerFields {
                    if let marker = (next.loops + next.shots).first(where: { $0.id == id }) {
                        time.text = Timecode.format(marker.frame, fps: next.framesPerSecond)
                    }
                }
                // Apply can be clicked repeatedly. Only rebuild the media graph
                // when its paths changed; metadata edits keep the loaded media.
                if previous.videoPath != next.videoPath || previous.audioPath != next.audioPath {
                    try loadProjectMedia()
                }
                refresh(); return true
            } catch { errorText.text = error.localizedDescription; return false }
        }
        _ = await dialog("Propriétés", content: stack([categories, errorText]), primary: "OK",
                         secondary: "Appliquer", close: "Annuler",
                         validatePrimary: apply, secondaryAction: { _ = apply() }, contentWidth: categories.width)
    }
}
