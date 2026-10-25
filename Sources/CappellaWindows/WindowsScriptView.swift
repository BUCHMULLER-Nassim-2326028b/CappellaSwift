import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func refreshScript() {
        if scriptRevision != self.document.revision {
            let cues = self.document.project.cues.sorted { $0.start < $1.start }
            scriptCues = cues; scriptPlaybackState = nil
            let order = cues.map(\.id)
            if order != scriptOrder {
                script.children.clear(); scriptRows.removeAll(); scriptModels.removeAll(); scriptSelection = nil; scriptFollowID = nil
                for cue in cues {
                    let header = label("", size: 11); header.fontFamily = FontFamily("Courier New")
                    let text = label("", size: 12); text.fontFamily = FontFamily("Courier New"); text.textWrapping = .wrap
                    let container = Border(); container.child = stack([header, text], spacing: 2)
                    container.padding = Thickness(left: 6, top: 3, right: 6, bottom: 3)
                    let id = cue.id
                    container.tapped.addHandler { [weak self] _, _ in
                        guard let self, let current = self.document.project.cues.first(where: { $0.id == id }) else { return }
                        media.stop(); self.document.selection = current.id; self.document.track = current.track
                        seek(current.start); refreshScript()
                    }
                    script.children.append(container); scriptRows[cue.id] = (container, header, text)
                }
                scriptOrder = order
            }
            let rolesChanged = scriptRoles != self.document.project.roles || scriptFPS != fps
            let names = Dictionary(uniqueKeysWithValues: self.document.project.roles.map { ($0.id, $0.name) })
            for cue in cues {
                guard let row = scriptRows[cue.id], rolesChanged || scriptModels[cue.id] != cue else { continue }
                let name = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
                let header = Timecode.format(cue.start, fps: fps) + " — " + name + " :"
                if row.header.text != header { row.header.text = header }
                if row.text.text != cue.text { row.text.text = cue.text }
            }
            scriptModels = Dictionary(uniqueKeysWithValues: cues.map { ($0.id, $0) })
            scriptRoles = self.document.project.roles; scriptFPS = fps
            scriptRevision = self.document.revision
        }
        refreshScriptPlayback()
    }
    func refreshScriptPlayback() {
        guard !videoOnly else { return }
        if scriptRevision != self.document.revision { refreshScript(); return }
        let revision = self.document.revision, frame = self.document.frame
        let restyle = scriptPlaybackRevision != revision || scriptPlaybackDark != dark
        guard restyle || scriptPlaybackFrame != frame || scriptSelection != self.document.selection else { return }
        if scriptPlaybackState?.contains(frame: frame) != true {
            scriptPlaybackState = DialogueScriptState(cues: scriptCues, frame: frame)
        }
        guard let state = scriptPlaybackState else { return }
        let affected = restyle ? Set(scriptRows.keys) : scriptActiveIDs.symmetricDifference(state.activeIDs)
        // No brush allocation or XAML setters unless a row actually changes.
        let normal = affected.isEmpty ? nil : ink(dark ? 0xE6E6E6 : 0x061424)
        let active = affected.isEmpty ? nil : ink(dark ? 0xFF9999 : 0xBA2020)
        for id in affected {
            guard let row = scriptRows[id] else { continue }
            let current = state.activeIDs.contains(id)
            row.header.foreground = current ? active : normal
            row.text.foreground = current ? active : normal
        }
        scriptActiveIDs = state.activeIDs; scriptSelection = self.document.selection
        scriptPlaybackRevision = revision; scriptPlaybackFrame = frame; scriptPlaybackDark = dark
        guard !self.document.editing, !dialogShowing, let id = state.followID,
              id != scriptFollowID || restyle else { return }
        scriptFollowID = id
        DispatchQueue.main.async { [weak self] in
            guard let self, !isClosed, !videoOnly, !dialogShowing, !self.document.editing,
                  scriptFollowID == id, let row = scriptRows[id] else { return }
            // Scroll only when the target leaves the visible area.
            if scriptScroll.viewportHeight > 0,
               let transform = try? row.border.transformToVisual(scriptScroll),
               let point = try? transform.transformPoint(WindowsFoundation.Point(x: 0, y: 0)),
               point.y >= 0, Double(point.y) + row.border.actualHeight <= scriptScroll.viewportHeight { return }
            let options = BringIntoViewOptions()
            options.animationDesired = false; options.verticalAlignmentRatio = 0.3
            try? row.border.startBringIntoView(options)
        }
    }
}
