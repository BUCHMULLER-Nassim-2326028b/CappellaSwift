import Foundation

public struct RythmoMovieOptions {
    public enum Sound: Int, CaseIterable, Hashable {
        case none, original, international
        public var title: String {
            switch self { case .none: return "Sans son"; case .original: return "VO"; case .international: return "VI" }
        }
    }
    public var height = 1080
    public var width: Int { height == 720 ? 1280 : 1920 }
    public var fps = 60
    public var startFrame: Int
    public var endFrame: Int
    public var includeVideo = true
    public var sound: Sound = .original
    public var duration: Double { Double(endFrame - startFrame) / Double(projectFPS) }
    public var projectFPS: Int
    public var frameCount: Int { Int(ceil(duration * Double(fps))) }
    public var bitRate: Int { height == 720 ? 6_000_000 : 12_000_000 }
    public init(project: Project, mediaDuration: Double = 0, international: Bool = false) {
        projectFPS = project.framesPerSecond
        startFrame = project.mediaStartFrame
        endFrame = max(startFrame + projectFPS, TimelineScrollRange.contentEnd(in: project),
                       startFrame + Int(max(0, mediaDuration.isFinite ? mediaDuration : 0) * Double(projectFPS)))
        sound = international ? .international : .original
    }
    public func validate() throws {
        guard [720, 1080].contains(height), [24, 25, 30, 60].contains(fps),
              projectFPS > 0, startFrame >= 0, endFrame > startFrame else {
            throw ProjectError.invalid("Choisissez une plage de timecodes valide et un format vidéo proposé.")
        }
    }
}

/// Thread-safe progress and cooperative cancellation for native export workers.
public final class MovieExportProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var amount = 0.0
    private var label = "Préparation des médias…"
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public func checkCancellation() throws {
        lock.lock(); let value = stopped; lock.unlock()
        if value || Task.isCancelled { throw CancellationError() }
    }
    public func update(_ value: Double, message: String = "Exportation MP4…") {
        lock.lock(); amount = value; label = message; lock.unlock()
    }
    public func encodedFrame(_ count: Int, total: Int) {
        update(Double(count) / Double(max(1, total)), message: "Exportation MP4… \(count) / \(total) images")
    }
    public var snapshot: (Double, String) {
        lock.lock(); defer { lock.unlock() }; return (amount, label)
    }
}
