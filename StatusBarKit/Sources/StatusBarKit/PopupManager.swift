import AppKit

@MainActor
public final class PopupManager {
    public static let shared = PopupManager()
    private weak var activePopup: PopupPanel?

    private init() {}

    public func willShow(_ popup: PopupPanel) {
        if activePopup !== popup {
            activePopup?.hidePopup()
        }
        activePopup = popup
    }

    public func didHide(_ popup: PopupPanel) {
        if activePopup === popup { activePopup = nil }
    }
}
