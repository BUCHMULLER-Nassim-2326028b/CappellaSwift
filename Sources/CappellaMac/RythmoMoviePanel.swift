import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore

struct RythmoMoviePanel: View {
    let project: Project
    let pixelsPerSecond: Double
    let videoOffset: Double
    @State var options: RythmoMovieOptions
    @Environment(\.dismiss) private var dismiss
    @State private var start = "", end = "", error = ""
    @State private var progress: MovieExportProgress?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exporter la rythmo en MP4").font(.headline)
            if let progress {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let snapshot = progress.snapshot
                    Text(snapshot.1)
                    ProgressView(value: snapshot.0)
                    Text(String(format: "%.1f %%", snapshot.0 * 100)).monospacedDigit()
                }
                Button("Annuler") { progress.cancel(); worker?.cancel() }
            } else {
                Text("Présentation du mode lecture, avec la bande et le panneau de contrôle.").font(.caption)
                Picker("Définition", selection: $options.height) { Text("1920 × 1080").tag(1080); Text("1280 × 720").tag(720) }
                Picker("Cadence", selection: $options.fps) { ForEach([24, 25, 30, 60], id: \.self) { Text("\($0) images/s").tag($0) } }
                TextField("Début", text: $start); TextField("Fin", text: $end)
                Toggle("Inclure la vidéo", isOn: $options.includeVideo)
                Picker("Son", selection: $options.sound) {
                    ForEach(RythmoMovieOptions.Sound.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
                HStack {
                    Spacer(); Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Exporter…", action: begin).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 440)
        .interactiveDismissDisabled(progress != nil)
        .onAppear {
            start = Timecode.format(options.startFrame, fps: options.projectFPS)
            end = Timecode.format(options.endFrame, fps: options.projectFPS)
        }
        .onDisappear { progress?.cancel(); worker?.cancel() }
    }
    private func begin() {
        do {
            guard let first = Timecode.parse(start, fps: options.projectFPS),
                  let last = Timecode.parse(end, fps: options.projectFPS) else {
                throw ProjectError.invalid("Timecode invalide : HH:MM:SS:II.")
            }
            options.startFrame = first; options.endFrame = last
            try options.validate()
            let picker = NSSavePanel(); picker.allowedContentTypes = [.mpeg4Movie]; picker.nameFieldStringValue = project.title + "-rythmo.mp4"
            guard picker.runModal() == .OK, let url = picker.url else { return }
            let token = MovieExportProgress(); progress = token; error = ""
            let settings = options
            worker = Task {
                do {
                    let job = Task.detached(priority: .utility) {
                        try await RythmoMovieExporter.export(project: project, options: settings, pixelsPerSecond: pixelsPerSecond, videoOffset: videoOffset, to: url, progress: token)
                    }
                    try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { token.cancel(); job.cancel() })
                    progress = nil; dismiss()
                } catch is CancellationError { progress = nil }
                catch { self.error = error.localizedDescription; progress = nil }
            }
        } catch { self.error = error.localizedDescription }
    }
}
