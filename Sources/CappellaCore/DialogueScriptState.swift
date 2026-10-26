import Foundation

/// Playback highlighting is independent of the editor's selected phrase.
public struct DialogueScriptState: Equatable {
    public let activeIDs: Set<UUID>
    public let activeLoopID: UUID?
    public let followID: UUID?
    /// The highlight and follow target are constant between these boundaries.
    public let validFrom: Int
    public let validUntil: Int

    public func contains(frame: Int) -> Bool { frame >= validFrom && frame < validUntil }

    public init(cues: [Cue], frame: Int, loops: [Marker] = []) {
        var lower = Int.min, upper = Int.max
        for cue in cues {
            let boundaries = cue.pendingEnd == true ? [cue.start] : [cue.start, cue.end]
            for boundary in boundaries {
                if boundary <= frame { lower = max(lower, boundary) }
                else { upper = min(upper, boundary) }
            }
        }
        var currentLoop: Marker?
        for loop in loops {
            if loop.frame <= frame {
                lower = max(lower, loop.frame)
                if currentLoop == nil || loop.frame >= currentLoop!.frame { currentLoop = loop }
            } else { upper = min(upper, loop.frame) }
        }
        activeLoopID = currentLoop?.id
        validFrom = lower; validUntil = upper
        var latestOnTrack: [Int: Int] = [:]
        for cue in cues where cue.start <= frame {
            latestOnTrack[cue.track] = max(latestOnTrack[cue.track] ?? cue.start, cue.start)
        }
        var active = Set<UUID>()
        var firstActive: Cue?, previous: Cue?, next: Cue?
        for cue in cues {
            if cue.start <= frame {
                if previous == nil || cue.start > previous!.start { previous = cue }
                let open = cue.pendingEnd == true && latestOnTrack[cue.track] == cue.start
                if open || (cue.pendingEnd != true && frame < cue.end) {
                    active.insert(cue.id)
                    if firstActive == nil || cue.start < firstActive!.start { firstActive = cue }
                }
            } else if next == nil || cue.start < next!.start { next = cue }
        }
        activeIDs = active
        followID = firstActive?.id ?? previous?.id ?? next?.id
    }
}