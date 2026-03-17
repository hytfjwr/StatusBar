import AppKit
import SwiftUI

// MARK: - PopupButtonStyle

/// Shared button style for popup menu items.
/// Provides hover background highlight and pointing-hand cursor.
public struct PopupButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = Theme.popupItemCornerRadius) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        PopupButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius
        )
    }
}

// MARK: - PopupButtonBody

private struct PopupButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered || configuration.isPressed ? .white.opacity(0.08) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .overlay(PointingHandCursor())
            .onHover { hovering in
                isHovered = hovering
            }
            .focusEffectDisabled()
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: - PointingHandCursor

/// NSViewRepresentable that sets the pointing-hand cursor via `addCursorRect`.
/// Works reliably on non-key NSPanels where NSCursor.push()/pop() fails.
private struct PointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> PointingHandCursorView {
        PointingHandCursorView()
    }

    func updateNSView(_ nsView: PointingHandCursorView, context: Context) {}
}

// MARK: - PointingHandCursorView

private final class PointingHandCursorView: NSView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        // Refresh cursor rects when the view resizes
        discardCursorRects()
        resetCursorRects()
    }
}
