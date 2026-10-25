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
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/BUCHMULLER-Nassim-2326028b/CappellaMac/releases/latest")!)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("CappellaMac", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    if userInitiated { message("Aucune version publiée", "Aucune mise à jour n'est encore disponible sur le dépôt Cappella.") }
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                struct Release: Decodable { let tag_name: String }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let available = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                let current = AppVersion.current
                if available.compare(current, options: .numeric) == .orderedDescending {
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
