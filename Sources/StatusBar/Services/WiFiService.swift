import CoreWLAN
import Foundation

enum WiFiService {
    /// Current Wi-Fi SSID, or nil when unavailable (no Wi-Fi, or no Location
    /// Services permission — macOS gates SSID access behind it).
    static func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
