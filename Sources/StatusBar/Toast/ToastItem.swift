import Foundation
import StatusBarKit

@MainActor
struct ToastItem: Identifiable {
    let id: String
    let request: ToastRequest
    var progress: Double?
    let action: (@MainActor () -> Void)?

    init(
        id: String = UUID().uuidString,
        request: ToastRequest,
        progress: Double? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.request = request
        self.progress = progress
        self.action = action
    }
}
