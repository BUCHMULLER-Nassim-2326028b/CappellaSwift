import SwiftUI
import AppKit
import CappellaCore

@MainActor
enum AppBranding {
    private static var defaultsObserver: NSObjectProtocol?
    private static var lastAppearance: String?
    private static var aboutWindow: NSWindow?

    static func install() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in updateDockIcon() }
            }
        }
        updateDockIcon()
    }
    private static func updateDockIcon() {
        let appearance = UserDefaults.standard.string(forKey: "general.appearance") ?? "light"
        guard appearance != lastAppearance else { return }
        lastAppearance = appearance
        let name = appearance == "dark" ? "AppIconDark" : "AppIcon"
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }
    static func logo(dark: Bool) -> NSImage? {
        let name = dark ? "CappellaLogo_dark" : "CappellaLogo"
        return Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
    static func showAbout() {
        if let aboutWindow { aboutWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = "À propos de Cappella"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @AppStorage("general.appearance") private var appearance = "light"
    private var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Cappella" }
    private var version: String { AppVersion.current }
    var body: some View {
        VStack(spacing: 14) {
            if let logo = AppBranding.logo(dark: appearance == "dark") {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 220, height: 165)
                    .accessibilityLabel("Logo Cappella")
            }
            Text(name).font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Logiciel d'origine développé par Chinkel.").font(.footnote)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Réécriture : nvssgoat").font(.body)
        }
        .padding(28).frame(width: 360, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
    }
}
