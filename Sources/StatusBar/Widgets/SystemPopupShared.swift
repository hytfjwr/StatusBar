import StatusBarKit
import SwiftUI

// MARK: - UsageBarRow

/// Labeled horizontal usage bar (capsule track + colored fill + trailing value).
struct UsageBarRow: View {
    let label: String
    let fraction: Double // 0...1 (clamped)
    let color: Color
    let valueText: String

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * clampedFraction)
                }
            }
            .frame(height: 5)

            Text(valueText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)
        }
    }
}

// MARK: - ProcessRow

/// Process list row: name + trailing badge.
struct ProcessRow: View {
    let name: String
    let valueText: String
    let valueColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            PopupStatusBadge(valueText, color: valueColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

// MARK: - PopupInfoRow

/// Static info row: icon + label + trailing value text (optional tap action).
struct PopupInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 22, alignment: .center)
                .symbolRenderingMode(.hierarchical)

            Text(label)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}
