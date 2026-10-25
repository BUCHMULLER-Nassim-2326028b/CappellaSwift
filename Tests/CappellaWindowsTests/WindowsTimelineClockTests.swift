import XCTest
@testable import CappellaWindows

final class WindowsTimelineClockTests: XCTestCase {
    func testRepeatedMediaPositionsDoNotSnapBackEveryQuarterSecond() {
        var clock = WindowsTimelineClock()
        _ = clock.position(sample: 0, rate: 1, advancing: true, now: 0)
        for step in 1...120 {
            let now = Double(step) / 240
            XCTAssertEqual(clock.position(sample: 0, rate: 1, advancing: true, now: now), now, accuracy: 1e-9)
        }
    }
    func testFreshCoarseSamplesCorrectVelocityWithoutPositionJumps() {
        for refreshRate in [60, 144, 240] {
            var clock = WindowsTimelineClock()
            var previous = clock.position(sample: 0, rate: 1, advancing: true, now: 0)
            for step in 1...refreshRate {
                let now = Double(step) / Double(refreshRate)
                let sample = (max(0, now - 0.02) * 10).rounded(.down) / 10
                let position = clock.position(sample: sample, rate: 1, advancing: true, now: now)
                XCTAssertGreaterThanOrEqual(position, previous)
                XCTAssertLessThanOrEqual(position - previous, 1.100001 / Double(refreshRate))
                previous = position
            }
            XCTAssertGreaterThan(previous, 0.9)
        }
    }
    func testReverseRemainsMonotonicAndBufferingStopsInterpolation() {
        var clock = WindowsTimelineClock()
        var previous = clock.position(sample: 10, rate: -1, advancing: true, now: 0)
        for step in 1...144 {
            let now = Double(step) / 144
            let sample = 10 - (now * 10).rounded(.down) / 10
            let position = clock.position(sample: sample, rate: -1, advancing: true, now: now)
            XCTAssertLessThanOrEqual(position, previous)
            previous = position
        }
        XCTAssertEqual(clock.position(sample: 9, rate: -1, advancing: false, now: 2), 9)
        XCTAssertEqual(clock.position(sample: 9, rate: -1, advancing: false, now: 3), 9)
        clock.reset()
        XCTAssertEqual(clock.position(sample: 5, rate: 1, advancing: true, now: 4), 5)
    }
}