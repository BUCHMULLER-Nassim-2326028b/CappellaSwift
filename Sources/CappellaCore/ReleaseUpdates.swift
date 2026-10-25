import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ReleaseUpdates {
    public static let page = "https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases"
    public struct Release: Decodable {
        public let tag_name: String
        public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
        public var isNewer: Bool { version.compare(AppVersion.current, options: .numeric) == .orderedDescending }
    }
    public static func latest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/BUCHMULLER-Nassim-2326028b/CappellaMac/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cappella", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
