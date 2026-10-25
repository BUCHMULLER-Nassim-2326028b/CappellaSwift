import SwiftUI
import AppKit
import CappellaSession

@MainActor
struct PreferencesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ApplicationPreferences.load()
    @State private var error: String?
    @State private var systemFontFamilies = NSFontManager.shared.availableFontFamilies
    private var fontFamilies: [String] {
        let bundled = TimelineFont.defaultFontName
        let others = Set(systemFontFamilies + [draft.fontName]).filter { !$0.isEmpty && $0 != bundled }
        return [bundled] + others.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    @ObservedObject private var session = ProjectSession.shared

    var body: some View {
        VStack(spacing: 14) {
            Text("Préférences").font(.headline)
            TabView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Général") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Vérifier les mises à jour au lancement", isOn: $draft.checkUpdates)
                            Toggle("Préfixer les copies enregistrées par « Copie de »", isOn: $draft.prefixCopies)
                            Picker("Apparence", selection: $draft.appearance) {
                                Text("Clair").tag("light")
                                Text("Sombre").tag("dark")
                            }.frame(width: 260)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox("Sauvegarde automatique") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Activer la sauvegarde automatique", isOn: $draft.automaticSave)
                            Stepper("Intervalle : \(draft.saveInterval) min", value: $draft.saveInterval, in: 1...120)
                                .disabled(!draft.automaticSave)
                            if let url = session.lastAutomaticSaveURL {
                                Button("Afficher la dernière sauvegarde") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                            if let message = session.automaticSaveError { Text(message).font(.caption).foregroundStyle(.red) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    Spacer(minLength: 0)
                }.padding(16).tabItem { Text("Général") }
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Fermer automatiquement les réacs", isOn: $draft.closeReactions)
                    Divider()
                    Picker("Police", selection: $draft.fontName) {
                        ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    HStack { Text("Taille"); Slider(value: $draft.fontSize, in: 16...42); Text("\(Int(draft.fontSize))") }
                    HStack { Text("Vitesse de défilement"); Slider(value: $draft.pixelsPerSecond, in: 15...800) }
                    HStack { Text("Hauteur"); Slider(value: $draft.bandHeight, in: 120...260) }
                    Toggle("Grille et signes", isOn: $draft.showGrid)
                    Toggle("Détection", isOn: $draft.showDetection)
                    Spacer(minLength: 0)
                }.padding(16).tabItem { Text("Bande rythmo") }
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Afficher l'écran de contrôle au lancement", isOn: $draft.showControlAtLaunch)
                    Divider()
                    Text("Décalage temporel de l'écran principal par rapport à l'écran de contrôle")
                    HStack {
                        Slider(value: $draft.videoOffsetMilliseconds, in: -1000...1000, step: 10)
                        Text("\(Int(draft.videoOffsetMilliseconds)) ms").monospacedDigit().frame(width: 75, alignment: .trailing)
                    }
                    HStack { Text("En retard"); Spacer(); Text("En avance") }.font(.caption).foregroundStyle(.secondary)
                    Button("Réinitialiser le décalage") { draft.videoOffsetMilliseconds = 0 }
                    Spacer(minLength: 0)
                }.padding(16).tabItem { Text("Vidéo") }
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    do {
                        try draft.validate()
                        guard draft.save() else { throw ProjectError.invalid("Impossible d'enregistrer les préférences.") }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 560, height: 425)
        .alert("Préférences", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
