import SwiftUI
import CappellaCore

struct ScriptExportPanel: View {
    let roles: [Role]
    let export: (ScriptExportOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options = ScriptExportOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Formatage du document").font(.headline)
            GroupBox("Présentation") {
                VStack(alignment: .leading) {
                    Toggle("Page de garde", isOn: $options.coverPage)
                    Toggle("Croisillé", isOn: $options.crossTable)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Liste des rôles") {
                Picker("Liste des rôles", selection: $options.roleList) {
                    ForEach(ScriptExportOptions.RoleList.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }.pickerStyle(.radioGroup).labelsHidden().padding(6)
            }
            GroupBox("Script") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Script", selection: $options.style) {
                        ForEach(ScriptExportOptions.Style.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                    }.pickerStyle(.radioGroup).labelsHidden()
                    Toggle("TC Out", isOn: $options.timecodeOut).disabled(options.style != .documentary)
                    Picker("Rôle", selection: $options.roleID) {
                        Text("Tous").tag(UUID?.none)
                        ForEach(roles) { Text($0.name).tag(Optional($0.id)) }
                    }
                }.padding(6)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { export(options) }.keyboardShortcut(.defaultAction).disabled(!options.hasContent)
            }
        }.padding(20).frame(width: 390)
    }
}
