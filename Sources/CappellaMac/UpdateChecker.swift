import AppKit
import Foundation
import CappellaCore

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var checking = false
    func check(userInitiated: Bool = false) {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                guard let release = try await ReleaseUpdates.latest() else {
                    if userInitiated { message("Aucune version publiée", "Aucune mise à jour n'est encore disponible sur le dépôt Cappella.") }
                    return
                }
                let current = AppVersion.current
                if release.isNewer {
                    let alert = NSAlert(); alert.messageText = "Une mise à jour est disponible"
                    alert.informativeText = "Cappella \(release.tag_name) est disponible. Version actuelle : \(current)."
                    alert.addButton(withTitle: "Voir la version"); alert.addButton(withTitle: "Plus tard")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases/latest")!)
                    }
                } else if userInitiated { message("Cappella est à jour", "Vous utilisez la version \(current).") }
            } catch {
                if userInitiated { message("Vérification impossible", error.localizedDescription) }
            }
        }
    }
    private func message(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
}
