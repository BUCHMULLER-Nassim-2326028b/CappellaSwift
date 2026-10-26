import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation

extension WindowsEditor {
    func exportRythmoMovie() async {
        guard !dialogShowing, !isClosed else { return }
        media.stop(); self.document.finishEditing(); updateTextEditor()
        if !readingMode { toggleReadingMode() }
        let project = self.document.project
        var options = RythmoMovieOptions(project: project, mediaDuration: media.duration, international: media.usingVI)
        let definition = ComboBox(); definition.items.append("1920 × 1080"); definition.items.append("1280 × 720"); definition.selectedIndex = 0
        let cadence = ComboBox(); let rates = [24, 25, 30, 60]
        for rate in rates { cadence.items.append("\(rate) images/s") }; cadence.selectedIndex = 3
        let start = textField(Timecode.format(options.startFrame, fps: fps)), end = textField(Timecode.format(options.endFrame, fps: fps))
        let picture = CheckBox(); picture.content = "Inclure la vidéo"; picture.isChecked = true
        let sound = ComboBox()
        for value in RythmoMovieOptions.Sound.allCases { sound.items.append(value.title) }
        sound.selectedIndex = Int32(options.sound.rawValue)
        let validationMessage = dialogError()
        let content = stack([
            dialogHint("Présentation du mode lecture, avec la bande et le panneau de contrôle."),
            dialogColumns([dialogField("Définition", definition), dialogField("Cadence", cadence)]),
            dialogColumns([dialogField("Début", start), dialogField("Fin", end)]),
            picture, dialogField("Son", sound), validationMessage
        ], spacing: 16)
        guard await dialog("Exporter la rythmo en MP4", content: content, primary: "Exporter…", close: "Annuler", validatePrimary: {
            guard let a = Timecode.parse(start.text, fps: project.framesPerSecond), let b = Timecode.parse(end.text, fps: project.framesPerSecond) else {
                validationMessage.text = "Timecode invalide : HH:MM:SS:II."; return false
            }
            options.startFrame = a; options.endFrame = b
            options.height = definition.selectedIndex == 1 ? 720 : 1080
            let rate = Int(cadence.selectedIndex)
            options.fps = rates.indices.contains(rate) ? rates[rate] : 60
            options.includeVideo = picture.isChecked == true
            options.sound = RythmoMovieOptions.Sound(rawValue: Int(sound.selectedIndex)) ?? .none
            do { try options.validate(); return true } catch { validationMessage.text = error.localizedDescription; return false }
        }, contentWidth: 460, defaultButton: .primary) == .primary else { return }
        let picker = FileSavePicker()
        do { try attachPicker(picker) } catch { await showError(error.localizedDescription); return }
        picker.suggestedFileName = project.title + "-rythmo"; picker.fileTypeChoices.insert("Vidéo MP4", [".mp4"].toVector())
        let destination: URL
        do {
            guard let file = try await picker.pickSaveFileAsync().get() else { return }
            destination = URL(fileURLWithPath: file.path)
        } catch { await showError(error.localizedDescription); return }
        let progress = MovieExportProgress(), settings = options
        let speed = self.document.preferences.pixelsPerSecond, offset = self.document.preferences.videoOffsetMilliseconds / 1000
        movieExportProgress = progress
        let job = Task.detached(priority: .utility) {
            try WindowsRythmoMovie.export(project: project, options: settings, pixelsPerSecond: speed, videoOffset: offset, destination: destination, progress: progress)
        }
        cancelMovieExport = { progress.cancel(); job.cancel() }
        defer { movieExportProgress = nil; cancelMovieExport = nil }
        let message = label("Préparation des médias…"); message.textWrapping = .wrap
        let percent = label("0 %", size: 24)
        let body = stack([message, percent])
        let timer = DispatcherTimer(); timer.interval = TimeSpan(duration: 1_000_000)
        timer.tick.addHandler { _, _ in
            let snapshot = progress.snapshot; message.text = snapshot.1; percent.text = String(format: "%.1f %%", snapshot.0 * 100)
        }
        var watcher: Task<Void, Never>?
        body.loaded.addHandler { [weak self] _, _ in
            guard watcher == nil, let current = self?.activeDialog else { return }
            watcher = Task { _ = try? await job.value; try? current.hide() }
        }
        try? timer.start()
        _ = await dialog("Exportation MP4", content: body, primary: "", close: "Annuler", contentWidth: 420)
        try? timer.stop(); progress.cancel(); job.cancel()
        do { try await job.value }
        catch is CancellationError { }
        catch { if !isClosed { await showError(error.localizedDescription) } }
        await watcher?.value
    }
}
