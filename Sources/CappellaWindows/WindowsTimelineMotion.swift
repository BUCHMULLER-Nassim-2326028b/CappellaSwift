import Foundation
import WinUI
import WinAppSDK
import WindowsFoundation

/// Movement runs on Windows Composition, independently of XAML layout and Swift.
@MainActor
final class WindowsTimelineMotion {
    private var visual: Visual?
    private var unavailable = false
    private var anchorTime = 0.0
    private var anchorOffset = 0.0
    private var correction = 0.0
    private var velocity = 0.0
    private var initialized = false

    func invalidate() { initialized = false }
    func stop() { try? visual?.stopAnimation("Translation.X"); initialized = false }

    func update(_ element: Canvas, offset: Double, speed: Double, fallback: CompositeTransform) {
        let now = ProcessInfo.processInfo.systemUptime
        do {
            if visual == nil && !unavailable {
                try ElementCompositionPreview.setIsTranslationEnabled(element, true)
                visual = try ElementCompositionPreview.getElementVisual(element)
            }
            guard let visual else { fallback.translateX = offset; return }
            let elapsed = max(0, now - anchorTime)
            let predicted = anchorOffset + velocity * elapsed + correction * min(1, elapsed / 0.25)
            let hardReset = !initialized || velocity != speed || abs(offset - predicted) > max(32, abs(speed) * 0.15)
            if speed == 0 {
                if hardReset || abs(anchorOffset - offset) > 0.001 {
                    try visual.stopAnimation("Translation.X")
                    try visual.properties.insertVector3("Translation", Vector3(x: Float(offset), y: 0, z: 0))
                    anchorOffset = offset; anchorTime = now; correction = 0; velocity = 0; initialized = true
                }
                return
            }
            // Do not submit another XAML/Composition property change each frame.
            // Small clock drift is corrected gradually, without a visible jump.
            guard hardReset || elapsed >= 20 || (elapsed >= 0.5 && abs(offset - predicted) > 1) else { return }
            let start = hardReset ? offset : predicted
            let compositor = visual.compositor!
            let easing = try compositor.createLinearEasingFunction()
            let animation = try compositor.createScalarKeyFrameAnimation()!
            animation.duration = TimeSpan(duration: 300_000_000)
            try animation.insertKeyFrame(0, Float(start), easing)
            try animation.insertKeyFrame(Float(0.25 / 30), Float(offset + speed * 0.25), easing)
            try animation.insertKeyFrame(1, Float(offset + speed * 30), easing)
            try visual.startAnimation("Translation.X", animation)
            anchorTime = now; anchorOffset = start; correction = offset - start
            velocity = speed; initialized = true
            fallback.translateX = 0
        } catch {
            try? visual?.stopAnimation("Translation.X")
            try? visual?.properties.insertVector3("Translation", Vector3())
            visual = nil; unavailable = true; initialized = false
            fallback.translateX = offset
        }
    }
}

/// MediaPlayer.Position can arrive in coarse steps. Interpolate between samples
/// with a monotonic clock; actual playback state prevents drift during buffering.
struct WindowsTimelineClock {
    private var lastSample: Double?
    private var estimate = 0.0
    private var lastTime = 0.0
    private var correction = 0.0

    mutating func reset() { lastSample = nil; correction = 0 }

    mutating func position(sample: Double, rate: Double, advancing: Bool, now: Double) -> Double {
        let elapsed = max(0, now - lastTime)
        defer { lastTime = now; lastSample = sample }
        guard let previous = lastSample, advancing else {
            estimate = sample; correction = 0; return sample
        }
        let predicted = estimate + elapsed * rate
        // An unchanged Position is an old measurement, not a request to jump
        // backwards. Only a fresh media timestamp can correct our phase.
        if sample != previous {
            let error = sample - predicted
            if abs(error) > max(0.25, abs(rate) * 0.25) {
                estimate = sample; correction = 0; return sample
            }
            correction = error
        }
        // Correct phase through velocity, never by stepping the position.
        // Time-based gain behaves the same at 60, 144 or 240 Hz; the slew limit
        // prevents small corrections from reversing the direction of travel.
        let limit = abs(rate) * elapsed * 0.1
        let adjustment = min(limit, max(-limit, correction * (1 - exp(-elapsed / 0.25))))
        estimate = predicted + adjustment
        correction -= adjustment
        return estimate
    }
}
