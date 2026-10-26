import AVFoundation
import AppKit
import CoreImage
import CappellaCore

/// Independent readers and writer: exporting never seeks the live player's media.
enum RythmoMovieExporter {
    static func export(project: Project, options: RythmoMovieOptions, pixelsPerSecond: Double,
                       videoOffset: Double, to destination: URL, progress: MovieExportProgress) async throws {
        try options.validate(); try progress.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-movie-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: staging) }
        let movie = options.includeVideo ? project.videoPath.map { AVURLAsset(url: URL(fileURLWithPath: $0)) } : nil
        let track = try await movie?.loadTracks(withMediaType: .video).first
        var videoReader: AVAssetReader?, videoOutput: AVAssetReaderTrackOutput?
        var transform = CGAffineTransform.identity
        if let movie, let track {
            transform = try await track.load(.preferredTransform)
            let reader = try AVAssetReader(asset: movie)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ProjectError.invalid("Vidéo incompatible avec l'export.") }
            reader.add(output)
            let firstTime = max(0, Double(options.startFrame - project.mediaStartFrame) / Double(options.projectFPS) + videoOffset)
            let movieDuration = try await movie.load(.duration).seconds
            guard movieDuration.isFinite, movieDuration > 0 else { throw ProjectError.invalid("La vidéo n'a pas de durée exploitable.") }
            // Include the source frame straddling a fractional in-point.
            let decodeStart = max(0, min(firstTime - 1, movieDuration - 1))
            reader.timeRange = CMTimeRange(start: CMTime(seconds: decodeStart, preferredTimescale: 60000),
                duration: CMTime(seconds: movieDuration - decodeStart, preferredTimescale: 60000))
            guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
            videoReader = reader; videoOutput = output
        }
        let audioURL = options.sound == .none ? nil : (project.audioPath ?? project.videoPath).map { URL(fileURLWithPath: $0) }
        var audioSource: MoviePCMSource?
        if let audioURL {
            if (try? PCMChannelPreparation.Stream(audioURL)) != nil {
                audioSource = try MoviePCMSource(sources: [audioURL], international: options.sound == .international)
            } else {
                let source = AVURLAsset(url: audioURL)
                let tracks = try await source.loadTracks(withMediaType: .audio)
                var files: [URL] = []
                for (index, track) in tracks.enumerated() {
                    try progress.checkCancellation()
                    guard let description = try await track.load(.formatDescriptions).first,
                          let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { throw CocoaError(.fileReadCorruptFile) }
                    let url = directory.appendingPathComponent("decoded-\(index).wav")
                    try StereoAudioPreparation.decode(asset: source, track: track, to: url, channels: Int(format.pointee.mChannelsPerFrame))
                    files.append(url)
                }
                if !files.isEmpty { audioSource = try MoviePCMSource(sources: files, international: options.sound == .international) }
                else if project.audioPath != nil { throw ProjectError.invalid("Aucune piste audio dans le fichier son.") }
            }
        }
        let writer = try AVAssetWriter(outputURL: staging, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: options.width, AVVideoHeightKey: options.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: options.bitRate, AVVideoExpectedSourceFrameRateKey: options.fps]
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ProjectError.invalid("Encodeur H.264 indisponible.") }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width, kCVPixelBufferHeightKey as String: options.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        let start = Double(options.startFrame - project.mediaStartFrame) / Double(options.projectFPS)
        let audioShift = project.audioPath == nil ? videoOffset : 0
        var audioInput: AVAssetWriterInput?
        if let audioSource {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSource.sampleRate == 44100 ? 44100 : 48000,
                AVNumberOfChannelsKey: audioSource.channelCount, AVEncoderBitRateKey: audioSource.channelCount == 1 ? 96000 : 192000])
            audio.expectsMediaDataInRealTime = false
            guard writer.canAdd(audio) else { throw ProjectError.invalid("Encodeur audio indisponible.") }
            writer.add(audio); audioInput = audio
        }
        progress.update(0, message: "Initialisation de l’encodeur MP4…")
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var succeeded = false
        defer {
            videoReader?.cancelReading()
            if !succeeded { writer.cancelWriting() }
        }
        guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
        let layout = ReadingLayout(project: project, pixelsPerSecond: pixelsPerSecond)
        let ci = CIContext(options: [.cacheIntermediates: false])
        var nextVideo = videoOutput?.copyNextSampleBuffer(), heldVideo: CMSampleBuffer?
        // Each input has an independent producer. Waiting for audio readiness
        // must never prevent the video input from receiving the next frame.
        async let audioPump: Void = writeAudio(audioSource, input: audioInput, writer: writer,
            options: options, sourceStart: start + audioShift, progress: progress)
        for index in 0..<options.frameCount {
            try progress.checkCancellation()
            let seconds = Double(index) / Double(options.fps)
            let target = start + seconds + videoOffset
            while let next = nextVideo, CMSampleBufferGetPresentationTimeStamp(next).seconds <= target + 1e-7 {
                heldVideo = next; nextVideo = videoOutput?.copyNextSampleBuffer()
            }
            while !input.isReadyForMoreMediaData {
                try progress.checkCancellation()
                if writer.status == .failed || writer.status == .cancelled { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            try autoreleasepool {
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw CocoaError(.fileWriteUnknown) }
                CVPixelBufferLockBaseAddress(buffer, []); defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: options.width, height: options.height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw CocoaError(.fileWriteUnknown) }
                context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: options.width, height: options.height))
                context.translateBy(x: 0, y: CGFloat(options.height)); context.scaleBy(x: CGFloat(options.width) / 1920, y: -CGFloat(options.height) / 1080)
                if target >= 0, let sample = heldVideo, let pixels = CMSampleBufferGetImageBuffer(sample) {
                    let image = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
                    if let cg = ci.createCGImage(image, from: image.extent) {
                        let fit = min(1440 / CGFloat(cg.width), 810 / CGFloat(cg.height))
                        let w = CGFloat(cg.width) * fit, h = CGFloat(cg.height) * fit
                        context.saveGState()
                        context.translateBy(x: (1440 - w) / 2, y: (810 + h) / 2); context.scaleBy(x: 1, y: -1)
                        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); context.restoreGState()
                    }
                }
                ReadingPainter.draw(layout.nodes(at: Double(options.startFrame) + seconds * Double(options.projectFPS)), in: context)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(options.fps))) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            }
            if index % 6 == 0 || index + 1 == options.frameCount { progress.encodedFrame(index + 1, total: options.frameCount) }
        }
        input.markAsFinished()
        try await audioPump
        if videoReader?.status == .failed { throw videoReader?.error ?? CocoaError(.fileReadCorruptFile) }
        writer.endSession(atSourceTime: CMTime(seconds: options.duration, preferredTimescale: 60000))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try progress.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) }
        else { try FileManager.default.moveItem(at: staging, to: destination) }
        succeeded = true; progress.update(1, message: "Exportation terminée.")
    }
    private static func writeAudio(_ source: MoviePCMSource?, input: AVAssetWriterInput?, writer: AVAssetWriter,
                                   options: RythmoMovieOptions, sourceStart: Double, progress: MovieExportProgress) async throws {
        guard let source, let input else { return }
        do {
            let stride = source.channelCount * source.bitsPerSample / 8
            var description = AudioStreamBasicDescription(mSampleRate: Double(source.sampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsPacked | (source.bitsPerSample == 8 ? 0 : kAudioFormatFlagIsSignedInteger),
                mBytesPerPacket: UInt32(stride), mFramesPerPacket: 1, mBytesPerFrame: UInt32(stride),
                mChannelsPerFrame: UInt32(source.channelCount), mBitsPerChannel: UInt32(source.bitsPerSample), mReserved: 0)
            var format: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr, let format else { throw CocoaError(.fileReadCorruptFile) }
            let total = Int(options.duration * Double(source.sampleRate))
            let offset = Int((sourceStart * Double(source.sampleRate)).rounded())
            var frame = 0
            while frame < total {
                try progress.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try progress.checkCancellation()
                    if writer.status == .failed || writer.status == .cancelled { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                let count = min(2048, total - frame), data = try source.read(frame: frame + offset, count: count)
                var block: CMBlockBuffer?
                guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                    blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: data.count,
                    flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { throw CocoaError(.fileWriteUnknown) }
                let copied = data.withUnsafeBytes {
                    CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
                }
                guard copied == kCMBlockBufferNoErr else { throw CocoaError(.fileWriteUnknown) }
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(source.sampleRate)),
                    presentationTimeStamp: CMTime(value: Int64(frame), timescale: Int32(source.sampleRate)), decodeTimeStamp: .invalid)
                var size = stride, sample: CMSampleBuffer?
                guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                    sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                    sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample,
                    input.append(sample) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                frame += count
            }
            input.markAsFinished()
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

}
