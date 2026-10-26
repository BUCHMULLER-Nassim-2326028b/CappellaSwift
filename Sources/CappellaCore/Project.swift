import Foundation

public struct Role: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var color: Int
    public var sourceID: String?
    public var hexColor: String?
    public var descriptionText: String?
    public var gender: String?
    public var imageData: Data?
    public init(id: UUID = UUID(), name: String, color: Int = 0) {
        self.id = id; self.name = name; self.color = color
    }
}

public struct Cue: Codable, Identifiable, Equatable {
    public var id: UUID
    public var roleID: UUID?
    public var start: Int
    public var end: Int
    public var text: String
    public var sourceIndex: Int?
    public var track: Int = 0
    public var signs: [SyncSign]?
    public var voice: String?
    public var pendingEnd: Bool?
    public var visibleAnchors: [SyncSign] { pendingEnd == true ? Array(anchors.dropLast()) : anchors }
    public init(id: UUID = UUID(), roleID: UUID? = nil, start: Int, end: Int, text: String = "") {
        self.id = id; self.roleID = roleID; self.start = start; self.end = end; self.text = text
    }
}

public struct Project: Codable, Equatable {
    public var formatVersion = 1
    public var title = "Sans titre"
    public var author = ""
    public var framesPerSecond = 25
    public var roles: [Role] = []
    public var cues: [Cue] = []
    public var mediaStartFrame: Int = 0
    public var originalDetX: Data?
    public var loops: [Marker] = []
    public var shots: [Marker] = []
    public var metadata: [String: String]?
    public var videoPath: String?
    public var audioPath: String?
    public var lastPositionFrame: Int?
    public var positions: [Marker]?
    public init() {}

    public func validate() throws {
        guard formatVersion == 1 else { throw ProjectError.invalid("Version de projet non prise en charge.") }
        guard [24, 25, 30].contains(framesPerSecond) else {
            throw ProjectError.invalid("Cadence non prise en charge (24, 25 ou 30 images/s).")
        }
        guard Set(roles.map(\.id)).count == roles.count, Set(cues.map(\.id)).count == cues.count else {
            throw ProjectError.invalid("Identifiants dupliqués.")
        }
        let names = roles.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count else {
            throw ProjectError.invalid("Les noms des rôles doivent être renseignés et distincts.")
        }
        guard mediaStartFrame >= 0, mediaStartFrame <= 999 * 3600 * framesPerSecond else {
            throw ProjectError.invalid("Origine média invalide.")
        }
        let ids = Set(roles.map(\.id))
        for cue in cues {
            guard cue.start >= 0, cue.end > cue.start, cue.end <= 999 * 3600 * framesPerSecond,
                  (0...15).contains(cue.track) else {
                throw ProjectError.invalid("Une phrase a des bornes temporelles ou une piste invalides.")
            }
            if let role = cue.roleID, !ids.contains(role) {
                throw ProjectError.invalid("Une phrase référence un rôle absent.")
            }
            if let signs = cue.signs {
                guard signs.count >= 2, signs.first?.frame == cue.start, signs.last?.frame == cue.end,
                      signs.first?.textOffset == 0, signs.last?.textOffset == cue.text.unicodeScalars.count,
                      Set(signs.map(\.id)).count == signs.count else {
                    throw ProjectError.invalid("Les signes doivent délimiter la phrase et son texte.")
                }
                for (left, right) in zip(signs, signs.dropFirst()) {
                    guard left.frame <= right.frame, left.textOffset <= right.textOffset,
                          left.textOffset >= 0, right.textOffset <= cue.text.unicodeScalars.count else {
                        throw ProjectError.invalid("Les signes ne suivent pas l'ordre du texte et du temps.")
                    }
                }
            }
        }
        for marker in loops + shots + (positions ?? []) {
            guard marker.frame >= 0, marker.frame <= 999 * 3600 * framesPerSecond else {
                throw ProjectError.invalid("Un repère a un timecode invalide.")
            }
        }
    }

    public static func decode(_ data: Data) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: data)
        try project.validate()
        return project
    }

    public func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct Marker: Codable, Identifiable, Equatable {
    public var id: UUID
    public var frame: Int
    public var label: String
    public var sourceIndex: Int?
    public init(frame: Int, label: String) { id = UUID(); self.frame = frame; self.label = label }
}

public struct SyncSign: Codable, Identifiable, Equatable {
    public var id: UUID
    public var frame: Int
    public var textOffset: Int
    public var kind: String
    public var sourceIndex: Int?
    public init(frame: Int, textOffset: Int, kind: String, sourceIndex: Int? = nil) {
        id = UUID(); self.frame = frame; self.textOffset = textOffset
        self.kind = kind; self.sourceIndex = sourceIndex
    }
}

public extension Cue {
    var anchors: [SyncSign] {
        signs ?? [SyncSign(frame: start, textOffset: 0, kind: "in_open"),
                  SyncSign(frame: end, textOffset: text.unicodeScalars.count, kind: "out_open")]
    }

    mutating func replaceText(_ newText: String) {
        let oldCount = text.unicodeScalars.count
        if var values = signs {
            for index in values.indices {
                values[index].textOffset = oldCount == 0 ? 0 : Int((Double(values[index].textOffset) * Double(newText.unicodeScalars.count) / Double(oldCount)).rounded())
            }
            values[0].textOffset = 0
            values[values.count - 1].textOffset = newText.unicodeScalars.count
            signs = values
        }
        text = newText
    }

    mutating func setBounds(start newStart: Int, end newEnd: Int) throws {
        guard newStart >= 0, newEnd > newStart else { throw ProjectError.invalid("La fin doit suivre le début.") }
        if var values = signs {
            let oldDuration = max(1, end - start)
            for index in values.indices {
                values[index].frame = newStart + Int((Double(values[index].frame - start) * Double(newEnd - newStart) / Double(oldDuration)).rounded())
            }
            values[0].frame = newStart; values[values.count - 1].frame = newEnd
            signs = values
        }
        start = newStart; end = newEnd
    }
}

public extension Project {
    mutating func shift(by delta: Int, includingMediaOrigin: Bool = false) throws {
        // Validate a copy first so a rejected shift never leaves a partial edit.
        try validate()
        let limit = 999 * 3600 * framesPerSecond
        guard delta >= -limit, delta <= limit else { throw ProjectError.invalid("Décalage trop grand.") }
        var copy = self
        for index in copy.cues.indices {
            copy.cues[index].start += delta; copy.cues[index].end += delta
            if var signs = copy.cues[index].signs {
                for i in signs.indices { signs[i].frame += delta }
                copy.cues[index].signs = signs
            }
        }
        for index in copy.loops.indices { copy.loops[index].frame += delta }
        for index in copy.shots.indices { copy.shots[index].frame += delta }
        if includingMediaOrigin {
            copy.mediaStartFrame += delta
            if let position = copy.lastPositionFrame { copy.lastPositionFrame = position + delta }
            if var positions = copy.positions {
                for index in positions.indices { positions[index].frame += delta }
                copy.positions = positions
            }
        }
        try copy.validate()
        self = copy
    }

    func scriptText() -> String {
        let names = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0.name) })
        let lines = scriptEntries().map { entry -> String in
            switch entry {
            case .loop(let marker): return "boucle " + marker.label + "\n"
            case .cue(let cue):
                let role = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
                return "\(Timecode.format(cue.start, fps: framesPerSecond)) - \(role) :\n\(cue.text)\n"
            }
        }
        return "\(title)\n\(author)\n\n" + lines.joined(separator: "\n")
    }

    func crossTableCSV() -> String {
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let sorted = loops.sorted { $0.frame < $1.frame }
        let ranges = sorted.isEmpty ? [Marker(frame: 0, label: "Programme")] : sorted
        var rows = [["Boucle", "Début"] + roles.map(\.name)]
        for (index, marker) in ranges.enumerated() {
            let end = index + 1 < ranges.count ? ranges[index + 1].frame : Int.max
            let counts = roles.map { role in String(cues.filter { $0.roleID == role.id && $0.start >= marker.frame && $0.start < end }.count) }
            rows.append([marker.label, Timecode.format(marker.frame, fps: framesPerSecond)] + counts)
        }
        return rows.map { $0.map(quoted).joined(separator: ";") }.joined(separator: "\r\n")
    }
}

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Timecodes non-drop-frame. Les cadences fractionnaires nécessiteront un modèle rationnel.
public enum Timecode {
    public static func format(_ frames: Int, fps: Int) -> String {
        guard fps > 0 else { return "--:--:--:--" }
        let f = max(0, frames)
        return String(format: "%02d:%02d:%02d:%02d", f / (fps * 3600), (f / (fps * 60)) % 60, (f / fps) % 60, f % fps)
    }

    public static func parse(_ text: String, fps: Int) -> Int? {
        guard [24, 25, 30].contains(fps) else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4, values[0] <= 999, values[1] < 60, values[2] < 60, values[3] < fps else { return nil }
        return ((values[0] * 60 + values[1]) * 60 + values[2]) * fps + values[3]
    }
}
