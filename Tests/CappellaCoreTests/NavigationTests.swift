import XCTest
@testable import CappellaCore

final class NavigationTests: XCTestCase {
    func testSnapIncludesLoopsShotsAndAllPhraseSignsWithoutDuplicates() {
        var project = Project()
        var cue = Cue(start: 100, end: 200, text: "Bonjour")
        cue.signs = [SyncSign(frame: 100, textOffset: 0, kind: "in_open"),
                     SyncSign(frame: 150, textOffset: 3, kind: "neutral"),
                     SyncSign(frame: 200, textOffset: 7, kind: "out_open")]
        project.cues = [cue]
        project.loops = [Marker(frame: 80, label: "1"), Marker(frame: 200, label: "2")]
        project.shots = [Marker(frame: 90, label: "1"), Marker(frame: 150, label: "2")]
        XCTAssertEqual(Timeline.snapFrames(in: project), [80, 90, 100, 150, 200])
        XCTAssertEqual(Timeline.adjacentFrame(in: Timeline.snapFrames(in: project), from: 100, direction: -1), 90)
        XCTAssertEqual(Timeline.adjacentFrame(in: Timeline.snapFrames(in: project), from: 150, direction: 1), 200)
        XCTAssertNil(Timeline.adjacentFrame(in: Timeline.snapFrames(in: project), from: 200, direction: 1))
    }

    func testRapidArrowNavigationNeverSticksOnFloatingPointFrameConversion() {
        let targets = Array(1...2000)
        for fps in [24, 25, 30] {
            var seconds = 0.0
            for expected in targets {
                let current = Timeline.frame(at: seconds, fps: fps, playing: false)
                guard let next = Timeline.adjacentFrame(in: targets, from: current, direction: 1) else {
                    return XCTFail("Navigation bloquée avant la fin")
                }
                XCTAssertEqual(next, expected)
                seconds = Double(next) / Double(fps)
            }
            for expected in targets.dropLast().reversed() {
                let current = Timeline.frame(at: seconds, fps: fps, playing: false)
                let previous = Timeline.adjacentFrame(in: targets, from: current, direction: -1)
                XCTAssertEqual(previous, expected)
                seconds = Double(expected) / Double(fps)
            }
        }
    }

    func testPlaybackDoesNotLoseAFrameAtFloatingPointBoundaries() {
        for fps in [24, 25, 30, 48, 50, 60] {
            for frame in [1, 29, 101, 900_001] {
                let seconds = Double(frame) / Double(fps)
                XCTAssertEqual(Timeline.frame(at: seconds, fps: fps, playing: true), frame)
            }
            XCTAssertEqual(Timeline.frame(at: 1 - 1e-6, fps: fps, playing: true), fps - 1)
        }
    }
    func testPlaybackKeepsFloorRoundingAndEmptyTimelineHasNoTarget() {
        XCTAssertEqual(Timeline.frame(at: 1.99, fps: 25, playing: true), 49)
        XCTAssertEqual(Timeline.frame(at: 1.99, fps: 25, playing: false), 50)
        XCTAssertNil(Timeline.adjacentFrame(in: [], from: 100, direction: 1))
        XCTAssertEqual(Timeline.snapFrames(in: Project()), [])
    }
}
