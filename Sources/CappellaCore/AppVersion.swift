import Foundation

/// Change this one value when starting the next development version.
/// Packagers use the same value unless an explicit version or v-prefixed tag
/// overrides it; the resolved version is stamped into the shipped application.
public enum AppVersion {
    public static let development = "1.0.1"

    public static let current: String = {
        #if os(Windows)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let stamp = executable.deletingLastPathComponent().appendingPathComponent("Resources/Version.txt")
        if let text = try? String(contentsOf: stamp, encoding: .utf8) {
            let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        }
        #else
        for key in ["CappellaVersion", "CFBundleShortVersionString"] {
            if let version = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               version.first?.isNumber == true { return version }
        }
        #endif
        return development
    }()
}
