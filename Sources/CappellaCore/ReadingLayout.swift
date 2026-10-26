import Foundation

public struct ReadingRect: Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct ReadingNode {
    public enum Content: Equatable {
        case rectangle(ReadingRect, UInt32)
        case text(String, x: Double, y: Double, size: Double, width: Double?, color: UInt32, underline: Bool)
    }
    public enum Layer: Equatable { case band, sidebar }
    public var id: String
    public var layer: Layer
    public var content: Content
}

/// Reference coordinates are identical in the live reader and the movie renderer.
/// Windows and Mac adapters only draw these primitives and the decoded video.
public final class ReadingLayout {
    public static let width = 1920.0, height = 1080.0
    public static let video = ReadingRect(0, 0, 1440, 810)
    public static let band = ReadingRect(0, 810, 1920, 270)
    public static let sidebar = ReadingRect(1440, 0, 480, 810)
    public static let font = "Arial"
    public let project: Project
    private let cues: [Cue]
    private let prefixEnds: [Double]
    private let loops: [Marker]
    private let shots: [Marker]
    private let names: [UUID: String]
    private let pixelsPerFrame: Double

    public init(project: Project, pixelsPerSecond: Double = 240) {
        self.project = project
        cues = project.cues.filter { (0..<4).contains($0.track) }.sorted {
            $0.start == $1.start ? $0.track < $1.track : $0.start < $1.start
        }
        var ends: [Double] = [], end = -Double.infinity
        for cue in cues {
            // Unfinished phrases keep their natural width; reserve enough space
            // to keep the draft visible without inventing an output sign.
            end = max(end, Double(cue.end), Double(cue.start) + (cue.pendingEnd == true ? 1200 : 0))
            ends.append(end)
        }
        prefixEnds = ends
        loops = project.loops.sorted { $0.frame < $1.frame }
        shots = project.shots.sorted { $0.frame < $1.frame }
        names = Dictionary(uniqueKeysWithValues: project.roles.map { ($0.id, $0.name) })
        pixelsPerFrame = min(800, max(15, pixelsPerSecond)) / Double(max(1, project.framesPerSecond))
    }

    public func nodes(at frame: Double) -> [ReadingNode] {
        let fps = project.framesPerSecond, beige: UInt32 = 0xDDD6AA
        var nodes: [ReadingNode] = []
        func rect(_ id: String, _ layer: ReadingNode.Layer, _ rect: ReadingRect, _ color: UInt32) {
            nodes.append(ReadingNode(id: id, layer: layer, content: .rectangle(rect, color)))
        }
        func text(_ id: String, _ layer: ReadingNode.Layer, _ value: String,
                  _ x: Double, _ y: Double, _ size: Double, width: Double? = nil,
                  color: UInt32 = 0, underline: Bool = false) {
            nodes.append(ReadingNode(id: id, layer: layer,
                content: .text(value, x: x, y: y, size: size, width: width, color: color, underline: underline)))
        }
        func x(_ value: Int) -> Double { 320 + (Double(value) - frame) * pixelsPerFrame }
        rect("band", .band, Self.band, beige)
        rect("sidebar", .sidebar, Self.sidebar, 0)
        let from = frame - 320 / pixelsPerFrame, to = frame + 1600 / pixelsPerFrame
        func visibleMarkers(_ values: [Marker]) -> ArraySlice<Marker> {
            var a = 0, b = values.count
            while a < b {
                let mid = (a + b) / 2
                if Double(values[mid].frame) < from { a = mid + 1 } else { b = mid }
            }
            let first = a; b = values.count
            while a < b {
                let mid = (a + b) / 2
                if Double(values[mid].frame) <= to { a = mid + 1 } else { b = mid }
            }
            return values[first..<a]
        }
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if prefixEnds[mid] < from { low = mid + 1 } else { high = mid }
        }
        for shot in visibleMarkers(shots) {
            rect("shot:" + shot.id.uuidString, .band, ReadingRect(x(shot.frame) - 1, 810, 2, 270), 0)
        }
        for loop in visibleMarkers(loops) {
            let id = loop.id.uuidString, left = x(loop.frame)
            rect("loop:" + id, .band, ReadingRect(left - 1, 810, 2, 270), 0x65604E)
            text("loop-label:" + id, .band, loop.label, left + 8, 1048, 24, color: 0x69624B)
        }
        for cue in cues.dropFirst(low) {
            if Double(cue.start) > to { break }
            let id = cue.id.uuidString, top = 810 + Double(cue.track) * 67.5
            if Double(cue.end) < from && cue.pendingEnd != true { continue }
            text("role:" + id, .band, cue.roleID.flatMap { names[$0] } ?? "Sans rôle", x(cue.start) - 115, top + 3, 14, width: nil)
            for (index, segment) in Timeline.segments(cue).enumerated() {
                let start = x(segment.start), width = Double(segment.end - segment.start) * pixelsPerFrame
                if start > 1920 || (!segment.naturalWidth && start + width < 0) { continue }
                text("cue:\(id):\(index)", .band, segment.text, start, top + 18, 36,
                     width: segment.naturalWidth ? nil : width, underline: cue.voice == "off")
            }
        }
        rect("playhead", .band, ReadingRect(319, 810, 2, 270), 0xDF5373)
        text("title", .sidebar, project.title, 1470, 14, 22, color: beige)
        text("time", .sidebar, Timecode.format(max(0, Int(frame.rounded(.down))), fps: fps), 1470, 48, 42, color: beige)
        let loop = loops.last { Double($0.frame) <= frame }
        rect("loop-badge", .sidebar, ReadingRect(1470, 110, 90, 48), beige)
        text("loop-number", .sidebar, loop?.label ?? "0", 1490, 117, 30)
        var nextIndex = 0, limit = cues.count
        while nextIndex < limit {
            let mid = (nextIndex + limit) / 2
            if Double(cues[mid].start) < frame { nextIndex = mid + 1 } else { limit = mid }
        }
        if nextIndex < cues.count {
            let next = cues[nextIndex]
            text("next-time", .sidebar, Timecode.format(next.start, fps: fps), 1570, 116, 28, color: beige)
        }
        // The role column is another time axis, so it scrolls continuously
        // instead of jumping a row whenever the next phrase starts.
        for cue in cues.dropFirst(max(0, nextIndex - 4)) {
            let y = 780 + (frame - Double(cue.start)) / Double(fps) * 70
            if y < 185 { break }
            guard y <= 780 else { continue }
            let name = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
            text("upcoming:" + cue.id.uuidString, .sidebar, name, 1474, y, 20, color: beige)
        }
        return nodes
    }
}
