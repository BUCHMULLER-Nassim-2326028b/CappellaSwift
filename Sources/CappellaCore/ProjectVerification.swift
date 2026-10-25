import Foundation

public enum ProjectVerification {
    public static func report(for project: Project) throws -> String {
        try project.validate()
        let cues = project.cues.sorted { $0.start < $1.start }
        var messages: [String] = []
        for cue in cues {
            let time = Timecode.format(cue.start, fps: project.framesPerSecond)
            if cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("\(time) : phrase vide.") }
            if cue.roleID == nil { messages.append("\(time) : rôle manquant.") }
        }
        for track in 0..<4 {
            let lane = cues.filter { $0.track == track }
            for (left, right) in zip(lane, lane.dropFirst()) where left.end > right.start {
                messages.append("Piste \(track + 1), \(Timecode.format(right.start, fps: project.framesPerSecond)) : chevauchement de phrases.")
            }
        }
        return messages.isEmpty
            ? "Aucune erreur détectée dans les contrôles disponibles : bornes, signes, rôles et chevauchements de phrases."
            : messages.joined(separator: "\n\n")
    }
}
