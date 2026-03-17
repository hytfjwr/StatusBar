import SwiftUI

// MARK: - PopupSection

/// Apple-style section header for popup menus.
/// Small, uppercase, secondary color — matches System Settings / Control Center style.
public struct PopupSectionHeader: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - PopupRow

/// Standard popup menu row with icon, label, and optional trailing content.
/// Larger touch targets and consistent spacing to match Apple's style.
public struct PopupRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let label: String
    let trailing: Trailing
    let action: () -> Void

    public init(
        icon: String,
        iconColor: Color = .primary,
        label: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.trailing = trailing()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 22, alignment: .center)
                    .symbolRenderingMode(.hierarchical)

                Text(label)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: Theme.popupItemCornerRadius, style: .continuous))
        }
        .buttonStyle(PopupButtonStyle())
    }
}

// MARK: - PopupStatusBadge

/// Small colored pill for status indicators (Connected, Running, etc.)
public struct PopupStatusBadge: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - PopupEmptyState

/// Centered empty state with icon and message.
public struct PopupEmptyState: View {
    let icon: String
    let message: String

    public init(icon: String, message: String) {
        self.icon = icon
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - PopupDivider

/// Subtle separator matching Apple's popup divider style.
public struct PopupDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}
