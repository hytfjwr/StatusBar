import AppKit
import Observation

/// Tracks the system appearance (Dark / Light) and publishes it as observable state.
///
/// Theme text colors and `BarContentView` read `isDark` instead of relying on the
/// inherited `NSAppearance`, so a system appearance switch becomes a single
/// observable change that can be animated as one cross-fade.
@MainActor
@Observable
final class AppearanceService {
    static let shared = AppearanceService()

    /// Duration of the cross-fade played when the system appearance changes.
    static let fadeDuration: TimeInterval = 0.35

    private(set) var isDark: Bool

    @ObservationIgnored
    private var observation: NSKeyValueObservation?

    private init() {
        isDark = Self.isDark(NSApplication.shared.effectiveAppearance)
    }

    func start() {
        guard observation == nil else {
            return
        }
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] app, _ in
            MainActor.assumeIsolated {
                self?.apply(app.effectiveAppearance)
            }
        }
        apply(NSApplication.shared.effectiveAppearance)
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    private func apply(_ appearance: NSAppearance) {
        let dark = Self.isDark(appearance)
        guard dark != isDark else {
            return
        }
        isDark = dark
    }

    /// Resolves an appearance to a light / dark flag.
    /// `bestMatch` collapses the vibrant and increased-contrast variants onto the
    /// two base appearances, so custom or future variants still map to one of them.
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The `NSAppearance` to pin on views that must not repaint until the fade runs.
    static func nsAppearance(isDark: Bool) -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
