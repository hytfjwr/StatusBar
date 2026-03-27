import Combine
import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class DiskUsageWidget: StatusBarWidget {
    let id = "disk-usage"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 60
    var sfSymbolName: String {
        "internaldrive"
    }

    private var snapshot: DiskService.DiskSnapshot?
    private var timer: AnyCancellable?
    private let service = DiskService()

    func start() {
        pollInBackground()
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollInBackground()
            }
    }

    private func pollInBackground() {
        Task.detached { [service] in
            let snap = service.poll()
            await MainActor.run { [weak self] in
                withAnimation(.numericTransition) {
                    self?.snapshot = snap
                }
            }
        }
    }

    func stop() {
        timer?.cancel()
    }

    private var iconStyle: AnyShapeStyle {
        guard let pct = snapshot?.usedPercent else {
            return AnyShapeStyle(.primary)
        }
        if pct >= 90 {
            return AnyShapeStyle(Theme.red)
        }
        if pct >= 80 {
            return AnyShapeStyle(Theme.yellow)
        }
        return AnyShapeStyle(.primary)
    }

    private var accessibilityDiskValue: String {
        guard let snap = snapshot else {
            return "Unknown"
        }
        return "\(snap.usedFormatted) of \(snap.totalFormatted)"
    }

    func body() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "internaldrive.fill")
                .font(Theme.sfIconFont)
                .foregroundStyle(iconStyle)
            Text("\(snapshot?.usedPercent ?? 0)%")
                .font(Theme.labelFont)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Disk Usage")
        .accessibilityValue(accessibilityDiskValue)
    }
}
