import AppKit
import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class FrontAppWidget: StatusBarWidget {
    let id = "front-app"
    let position: WidgetPosition = .left
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String {
        "app.fill"
    }

    private var appName = ""
    private var observer: NSObjectProtocol?

    func start() {
        appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            MainActor.assumeIsolated {
                let name = app.localizedName ?? ""
                self?.appName = name
                EventBus.shared.emit(IPCEventEnvelope(
                    event: .frontAppSwitched,
                    payload: .frontAppSwitched(appName: name, bundleID: app.bundleIdentifier)
                ))
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    func body() -> some View {
        HStack(spacing: 5) {
            AppIconView(appName: appName, size: 18)
            Text(appName)
                .font(Theme.labelFont)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active App")
        .accessibilityValue(appName)
    }
}
