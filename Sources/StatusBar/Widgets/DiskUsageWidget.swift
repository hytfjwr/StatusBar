import Combine
import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class DiskUsageWidget: StatusBarWidget, EventEmitting {
    let id = "disk-usage"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 60
    var sfSymbolName: String {
        "internaldrive"
    }

    private var snapshot: DiskService.DiskSnapshot?
    private var timer: AnyCancellable?
    private let service = DiskService()
    private var lastDiskThresholdLevel = 0 // 0=normal, 1=80%+, 2=90%+

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
                guard let self else {
                    return
                }
                withAnimation(.numericTransition) {
                    self.snapshot = snap
                }
                emitRaw(.diskUpdated(
                    usedPercent: snap.usedPercent,
                    usedBytes: snap.usedBytes,
                    totalBytes: snap.totalBytes
                ))
                let level = snap.usedPercent >= 90 ? 2 : snap.usedPercent >= 80 ? 1 : 0
                if level > lastDiskThresholdLevel {
                    let threshold = level == 2 ? 90 : 80
                    emit(.diskHigh(usedPercent: snap.usedPercent, threshold: threshold))
                }
                lastDiskThresholdLevel = level
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
