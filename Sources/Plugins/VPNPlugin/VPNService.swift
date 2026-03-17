import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "VPNService")

final class VPNService: @unchecked Sendable {
    struct VPNConnection {
        let name: String
        let isConnected: Bool
    }

    func fetchVPNs() async -> [VPNConnection] {
        do {
            let listOutput = try await ShellCommand.run("scutil", arguments: ["--nc", "list"])
            let lines = listOutput.split(separator: "\n")

            var connections: [VPNConnection] = []
            for line in lines {
                // Extract VPN name from quoted string
                guard let startQuote = line.firstIndex(of: "\""),
                      let endQuote = line[line.index(after: startQuote)...].firstIndex(of: "\"")
                else {
                    continue
                }

                let name = String(line[line.index(after: startQuote) ..< endQuote])
                let isConnected = line.contains("Connected")
                connections.append(VPNConnection(name: name, isConnected: isConnected))
            }

            return connections
        } catch {
            logger.debug("fetchVPNs failed: \(error.localizedDescription)")
            return []
        }
    }
}
