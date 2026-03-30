import Foundation

/// Resolves monitor-specific configuration by matching screen names against rules.
/// Pure, stateless — all inputs are parameters.
enum MonitorConfigResolver {

    /// Resolve the effective configuration for a screen.
    /// Rules are evaluated in order; the first match wins.
    /// `"*"` matches any screen name and is typically placed last as a fallback.
    static func resolve(
        screenName: String,
        rules: [MonitorMatchRule],
        globalAutoHide: Bool
    ) -> MonitorConfig {
        let matched = firstMatch(screenName: screenName, rules: rules)
        let autoHide = matched?.autoHide ?? globalAutoHide
        let widgetFilter = matched?.widgets.map { Set($0) }
        return MonitorConfig(autoHide: autoHide, widgetFilter: widgetFilter)
    }

    // MARK: - Private

    private static func firstMatch(
        screenName: String,
        rules: [MonitorMatchRule]
    ) -> MonitorMatchRule? {
        let lowered = screenName.lowercased()
        return rules.first { rule in
            if rule.match == "*" {
                return true
            }
            return lowered.contains(rule.match.lowercased())
        }
    }
}
