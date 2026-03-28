import StatusBarKit
import SwiftUI

private let toastSpring: Animation = .spring(response: 0.35, dampingFraction: 0.82)

// MARK: - ToastTrayView

struct ToastTrayView: View {
    private let manager = ToastManager.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(manager.toasts) { item in
                ToastCardView(item: item) {
                    withAnimation(toastSpring) {
                        manager.dismiss(id: item.id)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(4)
        .animation(toastSpring, value: manager.layoutVersion)
    }
}
