import AppKit

@MainActor
final class FrontAppService {
    var currentApp: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }
}
