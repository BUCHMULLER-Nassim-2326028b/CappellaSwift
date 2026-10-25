/// Font-independent, filled contours in a 20 x 25 coordinate space.
/// Based on the signs illustrated at cappella.app/documentation13.html#doc39.
/// Both renderers consume the same outlines, including sampled Bezier curves.
public enum SyncSignGeometry {
    public struct Point {
        public let x: Double
        public let y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    public static func outlines(for kind: String) -> [[Point]] {
        shapes[kind.lowercased()] ?? [[Point(9, 3), Point(11, 3), Point(11, 25), Point(9, 25)]]
    }

    private static func polygon(_ values: [(Double, Double)]) -> [Point] {
        values.map { Point($0.0, $0.1) }
    }

    private static func curve(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> [Point] {
        (1...16).map { step in
            let t = Double(step) / 16, u = 1 - t
            return Point(u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                         u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
        }
    }

    private static let shapes: [String: [[Point]]] = {
        let arrow = polygon([(10,0),(20,15),(15,15),(15,25),(5,25),(5,15),(0,15)])
        let closed = arrow.map { Point($0.x, 25 - $0.y) }
        let labial = polygon([(0,13),(5,13),(5,17),(15,17),(15,13),(20,13),
                              (20,25),(15,25),(15,21),(5,21),(5,25),(0,25)])
        let dental = [polygon([(0,13),(5,13),(20,25),(15,25)]),
                      polygon([(15,13),(20,13),(5,25),(0,25)])]
        let neutral = polygon([(10,9),(20,25),(0,25)])
        var a = [Point(0,12), Point(20,12)]
        a += curve(Point(20,12), Point(20,17), Point(15,25), Point(10,25))
        a += curve(Point(10,25), Point(5,25), Point(0,17), Point(0,12))
        let o = a.map { Point($0.x, 37 - $0.y) }
        var lips = [Point(10,0)]
        lips += curve(Point(10,0), Point(23.333,0), Point(23.333,12), Point(10,12))
        lips += curve(Point(10,12), Point(-3.333,12), Point(-3.333,0), Point(10,0))
        let tail = polygon([(7,11),(13,11),(20,25),(16,25),(10,18),(4,25),(0,25)])
        return ["in_open": [arrow], "out_open": [arrow],
                "in_close": [closed], "out_close": [closed],
                "mpb": [labial], "fvr": dental, "neutral": [neutral],
                "weuque": [lips, tail], "weuqueu": [lips, tail], "a": [a], "o": [o]]
    }()
}
