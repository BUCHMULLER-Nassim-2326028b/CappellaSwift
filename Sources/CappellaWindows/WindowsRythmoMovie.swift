import Foundation
import CappellaCore
import CWindowsInterop
import WinSDK

private final class MovieDrawing {
    var nodes: [ReadingNode] = []
    func draw(_ dc: UnsafeMutableRawPointer?) {
        for node in nodes {
            let sidebar: Int32 = node.layer == .sidebar ? 1 : 0
            switch node.content {
            case .rectangle(let rect, let color):
                cappella_movie_rect(dc, rect.x, rect.y, rect.width, rect.height, color, sidebar)
            case .text(let value, let x, let y, let size, let width, let color, let underline):
                (Array(value.utf16) + [0]).withUnsafeBufferPointer {
                    cappella_movie_text(dc, $0.baseAddress, x, y, size, width ?? -1, color, underline ? 1 : 0, sidebar)
                }
            }
        }
    }
}

enum WindowsRythmoMovie {
    private static func check(_ status: Int32) throws {
        guard status >= 0 else {
            throw ProjectError.invalid("Exportation MP4 impossible (Media Foundation : \(String(UInt32(bitPattern: status), radix: 16))).")
        }
    }
    static func export(project: Project, options: RythmoMovieOptions, pixelsPerSecond: Double,
                       videoOffset: Double, destination: URL, progress: MovieExportProgress) throws {
        try options.validate(); try progress.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-movie-" + Foundation.UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent("." + Foundation.UUID().uuidString + ".mp4")
        var audio: MoviePCMSource?
        defer {
            audio = nil
            try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: staging)
        }
        if options.sound != .none, let path = project.audioPath ?? project.videoPath {
            let source = URL(fileURLWithPath: path)
            var files: [URL] = []
            if (try? PCMChannelPreparation.Stream(source)) != nil { files = [source] }
            else {
                var ordinal: Int32 = 0, streams: Int32 = 0
                repeat {
                    try progress.checkCancellation()
                    let decoded = directory.appendingPathComponent("decoded-\(ordinal).wav")
                    var duration = 0.0
                    let status = (Array(source.path.utf16) + [0]).withUnsafeBufferPointer { input in
                        (Array(decoded.path.utf16) + [0]).withUnsafeBufferPointer { output in
                            cappella_decode_audio(input.baseAddress, output.baseAddress, ordinal, &streams, &duration, { Task.isCancelled ? 1 : 0 })
                        }
                    }
                    try progress.checkCancellation(); try check(status)
                    if status == 0 { files.append(decoded) }
                    ordinal += 1
                } while ordinal < streams
            }
            if !files.isEmpty {
                audio = try MoviePCMSource(sources: files, international: options.sound == .international)
            } else if project.audioPath != nil { throw ProjectError.invalid("Aucune piste audio dans le fichier son.") }
        }
        progress.update(0, message: "Initialisation de l’encodeur MP4…")
        var status: Int32 = 0
        let video = options.includeVideo ? project.videoPath ?? "" : ""
        let handle = (Array(staging.path.utf16) + [0]).withUnsafeBufferPointer { output in
            (Array(video.utf16) + [0]).withUnsafeBufferPointer { input in
                cappella_movie_create(output.baseAddress, input.baseAddress, Int32(options.width), Int32(options.height), Int32(options.fps), Int32(options.bitRate),
                    Int32(audio?.sampleRate ?? 0), Int32(audio?.channelCount ?? 0), Int32(audio?.bitsPerSample ?? 0), &status)
            }
        }
        try check(status)
        guard let handle else { throw ProjectError.invalid("Encodeur MP4 indisponible.") }
        var open = true
        defer { if open { cappella_movie_close(handle) } }
        let layout = ReadingLayout(project: project, pixelsPerSecond: pixelsPerSecond), drawing = MovieDrawing()
        let pointer = Unmanaged.passUnretained(drawing).toOpaque()
        let start = Double(options.startFrame - project.mediaStartFrame) / Double(options.projectFPS)
        var audioFrame = 0
        for index in 0..<options.frameCount {
            try progress.checkCancellation()
            let seconds = Double(index) / Double(options.fps)
            drawing.nodes = layout.nodes(at: Double(options.startFrame) + seconds * Double(options.projectFPS))
            try check(cappella_movie_frame(handle, start + seconds + videoOffset, Int64(index), { dc, context in
                guard let context else { return }
                Unmanaged<MovieDrawing>.fromOpaque(context).takeUnretainedValue().draw(dc)
            }, pointer))
            if let audio {
                let end = min(Int((seconds + 1 / Double(options.fps)) * Double(audio.sampleRate)), Int(options.duration * Double(audio.sampleRate)))
                let shift = Int((start + (project.audioPath == nil ? videoOffset : 0)) * Double(audio.sampleRate))
                while audioFrame < end {
                    try progress.checkCancellation()
                    let count = min(2048, end - audioFrame)
                    let data = try audio.read(frame: audioFrame + shift, count: count)
                    try data.withUnsafeBytes { bytes in
                        try check(cappella_movie_audio(handle, bytes.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), Int64(audioFrame)))
                    }
                    audioFrame += count
                }
            }
            if index % 6 == 0 || index + 1 == options.frameCount { progress.encodedFrame(index + 1, total: options.frameCount) }
        }
        try check(cappella_movie_finish(handle)); cappella_movie_close(handle); open = false
        try progress.checkCancellation()
        let moved = (Array(staging.path.utf16) + [0]).withUnsafeBufferPointer { source in
            (Array(destination.path.utf16) + [0]).withUnsafeBufferPointer { target in
                MoveFileExW(source.baseAddress, target.baseAddress, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            }
        }
        guard moved else { throw ProjectError.invalid("Impossible d'enregistrer le MP4 à cet emplacement.") }
        progress.update(1, message: "Exportation terminée.")
    }
}
