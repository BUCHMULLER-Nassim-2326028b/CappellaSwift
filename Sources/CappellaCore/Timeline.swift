import Foundation

public struct TimedText: Equatable {
    public var start: Int
    public var end: Int
    public var text: String
    public var naturalWidth = false
}

public enum Timeline {
    /// A stopped transport holds an exact requested frame, even when the
    /// seconds representation lies a fraction below that frame in binary.
    public static func frame(at seconds: Double, fps: Int, playing: Bool) -> Int {
        guard seconds.isFinite, fps > 0 else { return 0 }
        let value = max(0, seconds) * Double(fps)
        let nearest = value.rounded()
        // An exact frame represented in seconds can multiply back to n - 1 ULP.
        // Snap numerical noise only; real sub-frame positions keep floor rounding.
        if abs(value - nearest) <= max(1e-9, value.ulp * 4) { return Int(nearest) }
        return Int(value.rounded(playing ? .down : .toNearestOrAwayFromZero))
    }

    public static func snapFrames(in project: Project) -> [Int] {
        let signs = project.cues.flatMap { $0.visibleAnchors.map(\.frame) }
        return Array(Set(signs + project.loops.map(\.frame) + project.shots.map(\.frame))).sorted()
    }

    public static func adjacentFrame(in frames: [Int], from current: Int, direction: Int) -> Int? {
        direction > 0 ? frames.lazy.filter { $0 > current }.min() : frames.lazy.filter { $0 < current }.max()
    }

    public static func segments(_ cue: Cue, editing: Bool = false) -> [TimedText] {
        if editing && cue.pendingEnd == true { return [TimedText(start: cue.start, end: cue.end, text: cue.text, naturalWidth: true)] }
        let anchors = cue.anchors
        return zip(anchors, anchors.dropFirst()).compactMap { left, right in
            guard right.frame > left.frame, left.textOffset >= 0,
                  right.textOffset <= cue.text.unicodeScalars.count, right.textOffset > left.textOffset else { return nil }
            let scalars = cue.text.unicodeScalars
            let a = scalars.index(scalars.startIndex, offsetBy: left.textOffset)
            let b = scalars.index(scalars.startIndex, offsetBy: right.textOffset)
            return TimedText(start: left.frame, end: right.frame, text: String(scalars[a..<b]),
                naturalWidth: cue.pendingEnd == true && right.id == anchors.last?.id)
        }
    }

    public static func textOffset(in cue: Cue, at frame: Int) -> Int {
        let anchors = cue.anchors
        guard let left = anchors.last(where: { $0.frame <= frame }) else { return 0 }
        guard let right = anchors.first(where: { $0.frame > frame }) else { return cue.text.unicodeScalars.count }
        let fraction = Double(frame - left.frame) / Double(max(1, right.frame - left.frame))
        return left.textOffset + Int((Double(right.textOffset - left.textOffset) * fraction).rounded())
    }

    public static func changeSignType(in cue: inout Cue, id: UUID, kind: String) {
        var signs = cue.anchors
        guard let index = signs.firstIndex(where: { $0.id == id }) else { return }
        let valid = index == 0 ? kind.hasPrefix("in_") :
            index == signs.count - 1 ? kind.hasPrefix("out_") : !kind.hasPrefix("in_") && !kind.hasPrefix("out_")
        guard valid else { return }
        signs[index].kind = kind; cue.signs = signs
    }
    public static func shiftTextAnchor(in cue: inout Cue, id: UUID?, by delta: Int) {
        var signs = cue.anchors
        guard let index = signs.firstIndex(where: { $0.id == id }), index > 0, index < signs.count - 1 else { return }
        signs[index].textOffset = min(signs[index + 1].textOffset, max(signs[index - 1].textOffset, signs[index].textOffset + delta))
        cue.signs = signs
    }
    public static func detachSign(in cue: inout Cue, id: UUID) {
        var signs = cue.anchors
        guard let index = signs.firstIndex(where: { $0.id == id }), index > 0, index < signs.count - 1 else { return }
        let left = signs[index - 1], right = signs[index + 1]
        let fraction = Double(signs[index].frame - left.frame) / Double(max(1, right.frame - left.frame))
        signs[index].textOffset = left.textOffset + Int((fraction * Double(right.textOffset - left.textOffset)).rounded())
        cue.signs = signs
    }

    public static func addSign(to cue: inout Cue, kind: String, frame: Int, textOffset: Int) throws {
        guard frame > cue.start, frame < cue.end, textOffset >= 0, textOffset <= cue.text.unicodeScalars.count else {
            throw ProjectError.invalid("Placer le signe à l'intérieur de la phrase.")
        }
        var signs = cue.anchors
        let index = signs.firstIndex(where: { $0.frame > frame }) ?? signs.count - 1
        guard signs[index - 1].textOffset <= textOffset, signs[index].textOffset >= textOffset else {
            throw ProjectError.invalid("Le signe doit respecter l'ordre du texte. Positionnez le curseur dans le texte.")
        }
        signs.insert(SyncSign(frame: frame, textOffset: textOffset, kind: kind), at: index)
        cue.signs = signs
    }

    public static func moveSign(in cue: inout Cue, id: UUID, to frame: Int) {
        var signs = cue.anchors
        guard let index = signs.firstIndex(where: { $0.id == id }) else { return }
        let lower = index == 0 ? 0 : signs[index - 1].frame
        let upper = index + 1 == signs.count ? max(frame, signs[index - 1].frame + 1) : signs[index + 1].frame
        let value = min(max(frame, lower), upper)
        if index == 0 { signs[index].frame = min(value, cue.end - 1); cue.start = signs[index].frame }
        else if index == signs.count - 1 { signs[index].frame = max(value, cue.start + 1); cue.end = signs[index].frame }
        else { signs[index].frame = value }
        cue.signs = signs
    }
}
