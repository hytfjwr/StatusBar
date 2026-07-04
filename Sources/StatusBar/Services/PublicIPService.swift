import Foundation

/// Fetches the public IP from api.ipify.org. Results are cached for 60s.
/// Only called while the network popup is open — never polled in the background.
actor PublicIPService {
    static let shared = PublicIPService()

    private var cached: (value: String, fetchedAt: Date)?
    private let cacheWindow: TimeInterval = 60

    func fetch() async -> String? {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < cacheWindow {
            return cached.value
        }

        guard let url = URL(string: "https://api.ipify.org") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIP(trimmed) else {
            return nil
        }

        cached = (value: trimmed, fetchedAt: Date())
        return trimmed
    }

    /// Guards against non-IP garbage responses (e.g. an HTML error page from a
    /// misbehaving proxy) before caching or surfacing the value in the UI.
    private func isValidIP(_ value: String) -> Bool {
        guard !value.isEmpty, value.count < 64 else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:%"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
