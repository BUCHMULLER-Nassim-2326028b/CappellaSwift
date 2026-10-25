import Foundation
import CappellaCore
import CWindowsInterop

/// Enumerated when opening Preferences, never on the playback/rendering path.
enum WindowsSystemFonts {
    static func families(including current: String) -> [String] {
        var installed: [String] = []
        let result = withUnsafeMutablePointer(to: &installed) { storage in
            cappella_system_font_families({ name, context in
                guard let name, let context else { return }
                context.assumingMemoryBound(to: [String].self).pointee.append(
                    String(decodingCString: name, as: UTF16.self))
            }, storage)
        }
        if result < 0 { installed = ["Arial", "Times New Roman", "Courier New", "Segoe UI"] }
        let bundled = ApplicationPreferences.defaultFontName
        let others = Set(installed + [current]).filter { !$0.isEmpty && $0 != bundled }
        return [bundled] + others.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
