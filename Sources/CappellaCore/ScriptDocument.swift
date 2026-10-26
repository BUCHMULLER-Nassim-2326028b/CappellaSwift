import Foundation

/// Shared chronological layout for the on-screen script and exported documents.
public enum ScriptEntry: Identifiable {
    case loop(Marker)
    case cue(Cue)

    public var id: String {
        switch self {
        case .loop(let marker): return "loop:" + marker.id.uuidString
        case .cue(let cue): return "cue:" + cue.id.uuidString
        }
    }
}

public extension Project {
    func scriptEntries(roleID: UUID? = nil) -> [ScriptEntry] {
        let phrases = cues.filter { roleID == nil || $0.roleID == roleID }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.track < $1.track
        }
        let markers = loops.enumerated().sorted {
            $0.element.frame == $1.element.frame ? $0.offset < $1.offset : $0.element.frame < $1.element.frame
        }.map(\.element)
        var entries: [ScriptEntry] = []
        entries.reserveCapacity(phrases.count + markers.count)
        var index = 0
        for cue in phrases {
            while index < markers.count && markers[index].frame <= cue.start {
                entries.append(.loop(markers[index])); index += 1
            }
            entries.append(.cue(cue))
        }
        for marker in markers.dropFirst(index) { entries.append(.loop(marker)) }
        return entries
    }
}

public struct ScriptExportOptions {
    public enum RoleList: Int, CaseIterable, Hashable {
        case none, loops, firstTimecode
        public var title: String {
            switch self {
            case .none: return "Pas de liste des rôles"
            case .loops: return "Liste des rôles avec boucles"
            case .firstTimecode: return "Liste des rôles avec premier timecode"
            }
        }
    }
    public enum Style: Int, CaseIterable, Hashable {
        case none, classic, documentary
        public var title: String {
            switch self {
            case .none: return "Pas de script"
            case .classic: return "Script classique"
            case .documentary: return "Script documentaire"
            }
        }
    }
    public var coverPage = true
    public var crossTable = true
    public var roleList: RoleList = .loops
    public var style: Style = .classic
    public var timecodeOut = false
    public var roleID: UUID?
    public init() {}
    public var hasContent: Bool { coverPage || crossTable || roleList != .none || style != .none }
}

/// UI-independent RTF output, including Unicode, tables and explicit page breaks.
public enum ScriptDocument {
    private enum Block {
        case paragraph(String, heading: Bool = false)
        case page
        case table([[String]])
    }

    public static func rtf(project: Project, options: ScriptExportOptions) -> Data {
        let blocks = blocks(project: project, options: options)
        var result = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Courier New;}}{\\colortbl;\\red186\\green32\\blue32;}\\uc1\\paperw11906\\paperh16838\\margl850\\margr850\\margt850\\margb850\\f0\\fs24\n"
        for block in blocks {
            switch block {
            case .page: result += "\\page\n"
            case .paragraph(let text, let heading):
                result += "\\pard\\sa160" + (heading ? "\\b\\cf0 " : "\\b0\\cf0 ") + escaped(text) + "\\par\n"
            case .table(let rows):
                let count = rows.map(\.count).max() ?? 1
                let documentary = rows.first?.first == "TC In" && rows.first?.last == "Texte"
                let edges: [Int]
                if documentary { edges = count == 4 ? [1500, 3000, 4600, 10200] : [1500, 3100, 10200] }
                else { edges = (1...max(1, count)).map { $0 * 10200 / max(1, count) } }
                for (rowIndex, row) in rows.enumerated() {
                    result += "\\trowd\\trgaph80" + (rowIndex == 0 ? "\\trhdr" : "")
                    for edge in edges { result += "\\cellx\(edge)" }
                    for cell in row {
                        result += "\\pard\\intbl\\fs20\\cf0" + (rowIndex == 0 ? "\\b " : "\\b0 ") + escaped(cell) + "\\cell "
                    }
                    result += "\\row\n"
                }
                result += "\\pard\\fs24\\b0\\cf0\\par\n"
            }
        }
        return Data((result + "}").utf8)
    }

    public static func text(project: Project, options: ScriptExportOptions) -> String {
        blocks(project: project, options: options).map { block in
            switch block {
            case .paragraph(let text, _): return text
            case .page: return "\u{000C}"
            case .table(let rows): return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }

    private static func blocks(project: Project, options: ScriptExportOptions) -> [Block] {
        let roles = project.roles.filter { options.roleID == nil || $0.id == options.roleID }
        let cues = project.cues.filter { options.roleID == nil || $0.roleID == options.roleID }.sorted { $0.start < $1.start }
        let loops = project.loops.sorted { $0.frame < $1.frame }
        func time(_ frame: Int) -> String { Timecode.format(frame, fps: project.framesPerSecond) }
        func loopName(_ frame: Int) -> String? { loops.last { $0.frame <= frame }?.label }
        var result: [Block] = []
        if options.coverPage {
            result.append(.paragraph(project.title, heading: true))
            if !project.author.isEmpty { result.append(.paragraph(project.author)) }
            if let role = roles.first, options.roleID != nil { result.append(.paragraph(role.name)) }
        }
        func section(_ title: String) {
            if !result.isEmpty { result.append(.page) }
            result.append(.paragraph(title, heading: true))
        }
        if options.crossTable {
            section("Croisillé")
            // Split wide casts into readable tables; all roles remain included.
            let ranges = loops.isEmpty ? [Marker(frame: Int.min, label: "Programme")] : loops
            for offset in stride(from: 0, to: max(1, roles.count), by: 5) {
                let cast = Array(roles.dropFirst(offset).prefix(5))
                var rows = [["Boucle", "Début"] + cast.map(\.name)]
                if let first = loops.first, cues.contains(where: { $0.start < first.frame }) {
                    rows.append(["Avant la première boucle", ""] + cast.map { role in
                        String(cues.filter { $0.roleID == role.id && $0.start < first.frame }.count)
                    })
                }
                for (index, marker) in ranges.enumerated() {
                    let end = index + 1 < ranges.count ? ranges[index + 1].frame : Int.max
                    let start = marker.frame == Int.min ? "" : time(marker.frame)
                    rows.append([marker.label, start] + cast.map { role in
                        String(cues.filter { $0.roleID == role.id && $0.start >= marker.frame && $0.start < end }.count)
                    })
                }
                result.append(.table(rows))
            }
        }
        if options.roleList != .none {
            section("Liste des rôles")
            for role in roles {
                let phrases = cues.filter { $0.roleID == role.id }
                let detail: String
                if options.roleList == .firstTimecode {
                    detail = phrases.first.map { time($0.start) } ?? "Aucune réplique"
                } else {
                    var seen = Set<String>()
                    let labels = phrases.compactMap { loopName($0.start) }.filter { seen.insert($0).inserted }
                    detail = labels.isEmpty ? "Aucune boucle" : "Boucles : " + labels.joined(separator: ", ")
                }
                result.append(.paragraph(role.name + " : " + detail))
            }
        }
        if options.style != .none {
            section(options.style.title)
            let header = ["TC In"] + (options.timecodeOut ? ["TC Out"] : []) + ["Rôle", "Texte"]
            var rows = [header]
            func flushDocumentaryRows() {
                if rows.count > 1 { result.append(.table(rows)) }
                rows = [header]
            }
            let names = Dictionary(uniqueKeysWithValues: project.roles.map { ($0.id, $0.name) })
            for entry in project.scriptEntries(roleID: options.roleID) {
                switch entry {
                case .loop(let marker):
                    flushDocumentaryRows()
                    result.append(.paragraph("boucle " + marker.label, heading: true))
                case .cue(let cue):
                    let role = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
                    if options.style == .classic {
                        result.append(.paragraph(time(cue.start) + " - " + role + " :\n" + cue.text))
                    } else {
                        let end = cue.pendingEnd == true ? "…" : time(cue.end)
                        rows.append([time(cue.start)] + (options.timecodeOut ? [end] : []) + [role, cue.text])
                    }
                }
            }
            flushDocumentaryRows()
        }
        return result
    }

    private static func escaped(_ value: String) -> String {
        var result = ""
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for unit in normalized.utf16 {
            switch unit {
            case 92, 123, 125: result += "\\" + String(UnicodeScalar(unit)!)
            case 10: result += "\\line "
            case 13: break
            case 9: result += "\\tab "
            case 32...126: result += String(UnicodeScalar(unit)!)
            default: result += "\\u\(Int16(bitPattern: unit))?"
            }
        }
        return result
    }
}
