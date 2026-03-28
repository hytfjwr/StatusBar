import StatusBarKit
import SwiftUI

struct ToastCardView: View {
    let item: ToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(levelColor)
                .font(Theme.sfIconFont)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.request.title)
                    .font(Theme.popupLabelFont)
                    .foregroundStyle(Theme.primary)

                if let message = item.request.message {
                    Text(message)
                        .font(Theme.smallFont)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(3)
                }

                if let progress = item.progress {
                    ProgressView(value: progress)
                        .tint(levelColor)
                }

                if let label = item.request.actionLabel, item.action != nil {
                    Button {
                        item.action?()
                        onDismiss()
                    } label: {
                        Text(label)
                            .font(Theme.smallFont)
                            .foregroundStyle(Theme.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 280)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        if let custom = item.request.icon {
            return custom
        }
        return switch item.request.level {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        @unknown default: "info.circle.fill"
        }
    }

    private var levelColor: Color {
        switch item.request.level {
        case .info: Theme.accentBlue
        case .success: Theme.green
        case .warning: Theme.yellow
        case .error: Theme.red
        @unknown default: Theme.accentBlue
        }
    }
}
