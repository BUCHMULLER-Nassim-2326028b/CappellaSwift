import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation

extension WindowsEditor {
    func scriptExportOptions() async -> ScriptExportOptions? {
        let cover = CheckBox(); cover.content = "Page de garde"; cover.isChecked = true
        let cross = CheckBox(); cross.content = "Croisillé"; cross.isChecked = true
        func radio(_ title: String, group: String, selected: Bool) -> RadioButton {
            let button = RadioButton(); button.content = title
            button.groupName = group; button.isChecked = selected
            return button
        }
        let lists = ScriptExportOptions.RoleList.allCases.map { radio($0.title, group: "exportRoles", selected: $0 == .loops) }
        let styles = ScriptExportOptions.Style.allCases.map { radio($0.title, group: "exportScript", selected: $0 == .classic) }
        let out = CheckBox(); out.content = "TC Out"; out.isEnabled = false; out.isChecked = false
        for (index, button) in styles.enumerated() {
            button.checked.addHandler { _, _ in out.isEnabled = index == ScriptExportOptions.Style.documentary.rawValue }
        }
        let roles = self.document.project.roles
        let role = ComboBox(); role.items.append("Tous")
        for item in roles { role.items.append(item.name) }
        role.selectedIndex = 0
        let listControls: [UIElement] = lists.map { $0 }
        var scriptControls: [UIElement] = styles.map { $0 }
        scriptControls += [out, dialogField("Rôle", role)]
        let content = stack([
            dialogSection("Présentation", [cover, cross]),
            dialogSection("Liste des rôles", listControls),
            dialogSection("Script", scriptControls)
        ], spacing: 16)
        let scroll = ScrollViewer(); scroll.content = content
        scroll.maxHeight = min(620, max(240, root.actualHeight - 220))
        scroll.verticalScrollBarVisibility = .auto; scroll.horizontalScrollBarVisibility = .disabled
        func draft() -> ScriptExportOptions {
            var options = ScriptExportOptions()
            options.coverPage = cover.isChecked == true; options.crossTable = cross.isChecked == true
            options.roleList = ScriptExportOptions.RoleList(rawValue: lists.firstIndex { $0.isChecked == true } ?? 0) ?? .none
            options.style = ScriptExportOptions.Style(rawValue: styles.firstIndex { $0.isChecked == true } ?? 0) ?? .none
            options.timecodeOut = out.isChecked == true
            let index = Int(role.selectedIndex) - 1
            options.roleID = roles.indices.contains(index) ? roles[index].id : nil
            return options
        }
        guard await dialog("Formatage du document", content: scroll, primary: "OK", close: "Annuler",
                           validatePrimary: { draft().hasContent }, contentWidth: 390, defaultButton: .primary) == .primary else { return nil }
        return draft()
    }
}
