import Foundation
import CappellaCore
import UWP
import WinUI
import WindowsFoundation

final class WindowsMedia {
    let video = MediaPlayer()
    let externalAudio = MediaPlayer()
    let viAudio = MediaPlayer()
    private var hasSeparateVI = false
    private var disposed = false
    private var audioSources: [URL] = []
    private var forwardPCM: [WindowsPCMSource] = []
    private var nativeAudioItem: MediaPlaybackItem?
    private var audioIsExternal = false
    private var audioOffset: Double { audioIsExternal ? 0 : videoOffset }
    private var reverseTask: Task<Void, Never>?
    private var reverseGeneration = UUID()
    private var reverseAudio: WindowsReverseAudio?
    private var reversePlayers: [MediaPlayer] = []
    private var reverseReady: Set<Int> = []
    private var reversePrepared = false
    private var reverseFailure: String?
    private var requestedPosition = 0.0
    private var lastReverseVideoPosition: Double?
    var usingExternalAudio = false
    var usingVI = false
    var videoOffset = 0.0
    var volume = 1.0
    var muted = false
    var playbackChanged: (() -> Void)?
    var rate = 0.0 { didSet { if rate != oldValue { playbackChanged?() } } }
    var failed: ((String) -> Void)?
    private(set) var hasMedia = false
    private(set) var hasVideo = false
    var clock: MediaPlayer { usingExternalAudio || !hasVideo ? externalAudio : video }
    private var reverseClockIndex: Int { usingVI && reversePlayers.count > 1 ? 1 : 0 }
    var waitingForReverseAudio: Bool {
        rate < 0 && (!reversePrepared || reverseReady.count < reversePlayers.count)
    }
    var usesPlaybackClock: Bool { rate > 0 || !reversePlayers.isEmpty }
    var isAdvancing: Bool {
        if rate < 0 {
            guard !waitingForReverseAudio, !reversePlayers.isEmpty else { return false }
            return reversePlayers[reverseClockIndex].playbackSession.playbackState == .playing
        }
        return clock.playbackSession.playbackState == .playing
    }
    var duration: Double { Double(clock.playbackSession.naturalDuration.duration) / 10_000_000 }
    var position: Double {
        if rate == 0 { return requestedPosition }
        if rate < 0 {
            guard !waitingForReverseAudio, let audio = reverseAudio, !reversePlayers.isEmpty else { return requestedPosition }
            let index = reverseClockIndex
            let reversed = Double(reversePlayers[index].playbackSession.position.duration) / 10_000_000
            return max(0, audio.durations[index] - reversed - audioOffset)
        }
        let seconds = Double(clock.playbackSession.position.duration) / 10_000_000
        return max(0, seconds - (usingExternalAudio ? audioOffset : videoOffset))
    }

    init() {
        video.autoPlay = false; externalAudio.autoPlay = false; viAudio.autoPlay = false
        for player in [video, externalAudio, viAudio] { player.realTimePlayback = true }
        connectAudioEvents()
        video.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture vidéo impossible.") }
        }
        externalAudio.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture audio impossible.") }
        }
    }
    /// WinRT positions use 100 ns ticks. Truncating a floating-point frame
    /// boundary can seek just BEFORE that frame (41 / 25 -> 16_399_999 ticks).
    /// Round toward the target's interior so the decoder receives that frame,
    /// not its predecessor. The adjustment is less than one 100 ns tick.
    private func seekPosition(_ seconds: Double) -> TimeSpan {
        TimeSpan(duration: Int64((max(0, seconds) * 10_000_000).rounded(.up)))
    }

    private func connectAudioEvents() {
        viAudio.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture VI impossible.") }
        }
        for player in [video, externalAudio, viAudio] {
            player.mediaOpened.addHandler { [weak self, weak player] _, _ in
                DispatchQueue.main.async {
                    guard let self, let player, !self.disposed, player.source != nil else { return }
                    self.applyAudio()
                    let offset = player === self.video ? self.videoOffset : self.audioOffset
                    var current = self.requestedPosition
                    if self.rate > 0 {
                        if player !== self.clock, self.clock.playbackSession.playbackState == .playing {
                            current = self.position
                        } else if player === self.externalAudio, self.hasVideo,
                                  self.video.playbackSession.playbackState == .playing {
                            current = Double(self.video.playbackSession.position.duration) / 10_000_000 - self.videoOffset
                        }
                    }
                    player.playbackSession.position = self.seekPosition(current + offset)
                    if self.rate > 0 {
                        player.playbackSession.playbackRate = self.rate
                        try? player.play()
                    }
                }
            }
        }
    }
    func open(videoPath: String?, audioPath: String?) throws {
        unload()
        if let path = videoPath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let source = try MediaSource.createFromUri(Uri(url.absoluteString))
            let item = MediaPlaybackItem(source)
            video.source = item; nativeAudioItem = item; hasMedia = true; hasVideo = true
            audioSources = [url]
        }
        if let path = audioPath, !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path) else {
                throw NSError(domain: "CappellaAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fichier audio introuvable : " + path])
            }
            audioIsExternal = true; usingExternalAudio = true; hasMedia = true
            let url = URL(fileURLWithPath: path)
            audioSources = [url]; nativeAudioItem = nil
            if ["wav", "aif", "aiff", "aifc"].contains(url.pathExtension.lowercased()),
               let reader = try? PCMChannelPreparation.Stream(url) {
                for channels in AudioRouting.versions(total: reader.channels) {
                    forwardPCM.append(try WindowsPCMSource(reader: reader, channels: channels))
                }
                externalAudio.source = try forwardPCM[0].playbackItem()
                if forwardPCM.count > 1 {
                    viAudio.source = try forwardPCM[1].playbackItem(); hasSeparateVI = true
                }
            } else {
                let item = MediaPlaybackItem(try MediaSource.createFromUri(Uri(url.absoluteString)))
                nativeAudioItem = item; externalAudio.source = item
            }
        }
        applyAudio()
    }
    private func clearReverseAudio() {
        reverseGeneration = UUID(); reverseTask?.cancel(); reverseTask = nil
        for player in reversePlayers { try? player.pause(); player.source = nil; try? player.close() }
        reversePlayers.removeAll(); reverseReady.removeAll()
        reverseAudio = nil; reversePrepared = false; reverseFailure = nil
    }
    func unload() {
        guard !disposed else { return }
        stop(); clearReverseAudio()
        video.source = nil; externalAudio.source = nil; viAudio.source = nil
        hasSeparateVI = false; audioSources = []; forwardPCM.removeAll(); nativeAudioItem = nil; audioIsExternal = false; requestedPosition = 0; lastReverseVideoPosition = nil
        usingExternalAudio = false; usingVI = false; hasVideo = false; hasMedia = false
    }
    /// Backward video seeks must not interrupt the independent audio clock.
    func synchronizeReverseVideo(_ seconds: Double) {
        guard !disposed else { return }
        requestedPosition = seconds
        if hasVideo {
            let target = max(0, seconds + videoOffset)
            guard lastReverseVideoPosition != target else { return }
            lastReverseVideoPosition = target
            video.playbackSession.position = seekPosition(target)
        }
    }
    func seek(_ seconds: Double) {
        guard !disposed else { return }
        requestedPosition = max(0, seconds)
        lastReverseVideoPosition = nil
        synchronizeReverseVideo(requestedPosition)
        let position = seekPosition(requestedPosition + audioOffset)
        if usingExternalAudio && externalAudio.source != nil { externalAudio.playbackSession.position = position }
        if hasSeparateVI { viAudio.playbackSession.position = position }
        if rate < 0 { seekReverseAudio(); startReverseAudio() }
    }
    private func seekReverseAudio() {
        guard let audio = reverseAudio else { return }
        let original = requestedPosition + audioOffset
        for (index, player) in reversePlayers.enumerated() where reverseReady.contains(index) {
            try? player.pause()
            let reversed = max(0, min(audio.durations[index], audio.durations[index] - original))
            // MediaPlayer queues the seek before Play, as in forward playback.
            // Waiting for SeekCompleted here can stall a direction change.
            let current = Double(player.playbackSession.position.duration) / 10_000_000
            if abs(current - reversed) > 0.001 {
                player.playbackSession.position = seekPosition(reversed)
            }
        }
    }
    private func prepareReverseAudio() {
        guard !reversePrepared, reverseTask == nil, reverseFailure == nil else { return }
        guard let source = audioSources.first else { reversePrepared = true; return }
        let generation = reverseGeneration
        reverseTask = Task { @MainActor [weak self] in
            do {
                let worker = Task.detached(priority: .utility) { try WindowsAudioPreparation.prepare(source) }
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                let audio = WindowsReverseAudio(files: prepared.reversedVersions, durations: prepared.durations)
                try Task.checkCancellation()
                guard let self, !self.disposed, self.reverseGeneration == generation else { return }
                self.reverseAudio = audio; self.reversePrepared = true; self.reverseTask = nil
                for (index, url) in audio.files.enumerated() {
                    let player = MediaPlayer()
                    player.autoPlay = false; player.realTimePlayback = true
                    self.reversePlayers.append(player)
                    player.mediaOpened.addHandler { [weak self] _, _ in
                        DispatchQueue.main.async {
                            guard let self, self.reverseGeneration == generation else { return }
                            self.reverseReady.insert(index)
                            self.seekReverseAudio(); self.startReverseAudio()
                        }
                    }
                    player.mediaFailed.addHandler { [weak self] _, args in
                        let message = args?.errorMessage ?? "Lecture du son inversé impossible."
                        DispatchQueue.main.async {
                            guard let self, self.reverseGeneration == generation else { return }
                            self.reverseAudioFailed(message)
                        }
                    }
                    player.source = MediaPlaybackItem(try MediaSource.createFromUri(Uri(url.absoluteString)))
                }
                self.startReverseAudio()
            } catch {
                guard let self, !Task.isCancelled, self.reverseGeneration == generation else { return }
                self.reverseTask = nil
                self.reverseAudioFailed(error.localizedDescription)
            }
        }
    }
    private func reverseAudioFailed(_ message: String) {
        let reversing = rate < 0
        if reversing { stop() }
        clearReverseAudio()
        reverseFailure = message
        // A background warm-up failure must not interrupt normal playback.
        if reversing { failed?(message) }
    }
    private func startReverseAudio() {
        guard rate < 0, !waitingForReverseAudio else { return }
        applyAudio()
        for player in reversePlayers {
            player.playbackSession.playbackRate = abs(rate)
            do { try player.play() } catch { reverseAudioFailed(error.localizedDescription); return }
        }
        playbackChanged?()
    }
    func setRate(_ value: Double) throws {
        guard !disposed else { return }
        if value < 0, let message = reverseFailure {
            throw NSError(domain: "CappellaReverseAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        if value > 0, rate > 0 {
            rate = value
            video.playbackSession.playbackRate = value
            externalAudio.playbackSession.playbackRate = value
            viAudio.playbackSession.playbackRate = value
            return
        }
        if value < 0, rate < 0, !waitingForReverseAudio {
            rate = value
            for player in reversePlayers { player.playbackSession.playbackRate = abs(value) }
            return
        }
        // Snapshot the active clock before pausing or publishing the new
        // direction. Preparation callbacks then use this position or a newer
        // position supplied by the timeline while the audio is loading.
        let current = rate == 0 ? requestedPosition : position
        try video.pause(); try externalAudio.pause(); try viAudio.pause()
        for player in reversePlayers { try player.pause() }
        requestedPosition = max(0, current)
        rate = value
        applyAudio()
        if value < 0 {
            lastReverseVideoPosition = nil
            synchronizeReverseVideo(requestedPosition)
            prepareReverseAudio()
            seekReverseAudio()
            startReverseAudio()
        } else if value > 0 {
            // Pausing leaves the forward player exactly where it stopped. A
            // redundant precise seek on resume forces another decode/buffer.
            let offset = usingExternalAudio ? audioOffset : videoOffset
            let currentForward = Double(clock.playbackSession.position.duration) / 10_000_000 - offset
            if abs(currentForward - requestedPosition) > 0.001 { seek(requestedPosition) }
            if hasVideo { video.playbackSession.playbackRate = value; try video.play() }
            if usingExternalAudio && externalAudio.source != nil { externalAudio.playbackSession.playbackRate = value; try externalAudio.play() }
            if hasSeparateVI { viAudio.playbackSession.playbackRate = value; try viAudio.play() }
        }
    }
    func stop() { try? setRate(0) }
    func dispose() {
        guard !disposed else { return }
        playbackChanged = nil; failed = nil
        stop(); clearReverseAudio()
        disposed = true; forwardPCM.removeAll(); nativeAudioItem = nil
        try? video.close(); try? externalAudio.close(); try? viAudio.close()
    }
    func toggleVI() {
        let current = position
        guard hasSeparateVI || (nativeAudioItem?.audioTracks.size ?? 0) > 1 else { failed?("Le média ne contient pas de version internationale distincte."); return }
        usingVI.toggle()
        if rate < 0 { requestedPosition = current; seekReverseAudio(); startReverseAudio() }
        applyAudio()
    }
    func applyAudio() {
        guard !disposed else { return }
        video.isMuted = muted || usingExternalAudio || rate < 0
        externalAudio.isMuted = muted || (hasSeparateVI && usingVI) || rate < 0
        viAudio.isMuted = muted || !usingVI || rate < 0
        if let tracks = nativeAudioItem?.audioTracks, tracks.size > 1 {
            let index: Int32 = usingVI ? 1 : 0
            if tracks.selectedIndex != index { tracks.selectedIndex = index }
        }
        video.volume = volume; externalAudio.volume = volume; viAudio.volume = volume
        for (index, player) in reversePlayers.enumerated() {
            player.isMuted = muted || rate >= 0 || (reversePlayers.count > 1 && index != (usingVI ? 1 : 0))
            player.volume = volume
        }

    }
    deinit { reverseTask?.cancel() }
}
