import Foundation
@testable import StatusBar
import Testing

// MARK: - BluetoothServiceSystemProfilerParsingTests

struct BluetoothServiceSystemProfilerParsingTests {

    @Test("Returns empty map for nil input")
    func nilInput() {
        #expect(BluetoothService.parseSystemProfilerJSON(nil).isEmpty)
    }

    @Test("Returns empty map for malformed JSON")
    func malformed() {
        let data = Data("{not json}".utf8)
        #expect(BluetoothService.parseSystemProfilerJSON(data).isEmpty)
    }

    @Test("Parses AirPods L/R/Case/Main from nested structure")
    func airPodsNested() throws {
        let json = """
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "AirPods Pro": {
                "device_address": "AA:BB:CC:DD:EE:FF",
                "device_batteryLevelMain": "75%",
                "device_batteryLevelLeft": "70%",
                "device_batteryLevelRight": "65%",
                "device_batteryLevelCase": "100%",
                "device_minorType": "Headphones"
              }
            }]
          }]
        }
        """
        let result = BluetoothService.parseSystemProfilerJSON(Data(json.utf8))
        let battery = try #require(result["aa:bb:cc:dd:ee:ff"])
        #expect(battery.main == 75)
        #expect(battery.left == 70)
        #expect(battery.right == 65)
        #expect(battery.caseLevel == 100)
    }

    @Test("Parses numeric battery values without percent suffix")
    func numericBattery() throws {
        let json = """
        {
          "devices": [{
            "Magic Mouse": {
              "device_address": "12:34:56:78:9A:BC",
              "device_batteryLevelMain": 55
            }
          }]
        }
        """
        let result = BluetoothService.parseSystemProfilerJSON(Data(json.utf8))
        let battery = try #require(result["12:34:56:78:9a:bc"])
        #expect(battery.main == 55)
        #expect(battery.left == nil)
    }

    @Test("Skips entries without any battery fields")
    func skipsUnbatteried() {
        let json = """
        {
          "device_title": {
            "Bluetooth Keyboard": {
              "device_address": "11:22:33:44:55:66"
            }
          }
        }
        """
        let result = BluetoothService.parseSystemProfilerJSON(Data(json.utf8))
        #expect(result.isEmpty)
    }

    @Test("Address is lowercased for stable lookup")
    func normalizesAddressCase() {
        let json = """
        {
          "d": {
            "AirPods": {
              "device_address": "AB:CD:EF:01:02:03",
              "device_batteryLevelLeft": "50%"
            }
          }
        }
        """
        let result = BluetoothService.parseSystemProfilerJSON(Data(json.utf8))
        #expect(result["ab:cd:ef:01:02:03"]?.left == 50)
        #expect(result["AB:CD:EF:01:02:03"] == nil)
    }
}

// MARK: - BluetoothBatteryAlertTrackerTests

struct BluetoothBatteryAlertTrackerTests {

    private func airPods(
        id: String = "airpods", left: Int?, right: Int?, caseLevel: Int? = nil
    ) -> BluetoothService.BluetoothDevice {
        BluetoothService.BluetoothDevice(
            id: id,
            name: "AirPods Pro",
            category: .headphones,
            batteryLevel: nil,
            leftBattery: left,
            rightBattery: right,
            caseBattery: caseLevel
        )
    }

    private func mouse(id: String = "mouse", battery: Int?) -> BluetoothService.BluetoothDevice {
        BluetoothService.BluetoothDevice(
            id: id,
            name: "Magic Mouse",
            category: .mouse,
            batteryLevel: battery,
            leftBattery: nil,
            rightBattery: nil,
            caseBattery: nil
        )
    }

    @Test("Returns no alerts when disabled, even below threshold")
    func disabled() {
        var tracker = BluetoothBatteryAlertTracker()
        let alerts = tracker.evaluate(devices: [mouse(battery: 5)], enabled: false, threshold: 20)
        #expect(alerts.isEmpty)
    }

    @Test("Fires once when crossing threshold, suppresses on next tick")
    func fireOnceOnCrossing() {
        var tracker = BluetoothBatteryAlertTracker()
        let first = tracker.evaluate(devices: [mouse(battery: 15)], enabled: true, threshold: 20)
        #expect(first.count == 1)
        #expect(first.first?.deviceName == "Magic Mouse")
        #expect(first.first?.percent == 15)
        #expect(first.first?.component == nil)

        let second = tracker.evaluate(devices: [mouse(battery: 14)], enabled: true, threshold: 20)
        #expect(second.isEmpty)
    }

    @Test("Re-arms and re-fires after battery rises above threshold and drops again")
    func reArmsAfterRise() {
        var tracker = BluetoothBatteryAlertTracker()
        _ = tracker.evaluate(devices: [mouse(battery: 15)], enabled: true, threshold: 20)

        let above = tracker.evaluate(devices: [mouse(battery: 60)], enabled: true, threshold: 20)
        #expect(above.isEmpty)

        let third = tracker.evaluate(devices: [mouse(battery: 10)], enabled: true, threshold: 20)
        #expect(third.count == 1)
        #expect(third.first?.percent == 10)
    }

    @Test("AirPods L and R tracked independently; Case excluded")
    func airPodsPerComponent() {
        var tracker = BluetoothBatteryAlertTracker()
        let alerts = tracker.evaluate(
            devices: [airPods(left: 15, right: 55, caseLevel: 5)],
            enabled: true, threshold: 20
        )
        #expect(alerts.count == 1)
        #expect(alerts.first?.component == "left")
        #expect(alerts.first?.percent == 15)

        let next = tracker.evaluate(
            devices: [airPods(left: 15, right: 18, caseLevel: 5)],
            enabled: true, threshold: 20
        )
        #expect(next.count == 1)
        #expect(next.first?.component == "right")
    }

    @Test("Disconnecting and reconnecting at a low level re-fires")
    func disconnectReconnect() {
        var tracker = BluetoothBatteryAlertTracker()
        _ = tracker.evaluate(devices: [mouse(battery: 10)], enabled: true, threshold: 20)

        let empty = tracker.evaluate(devices: [], enabled: true, threshold: 20)
        #expect(empty.isEmpty)

        let alerts = tracker.evaluate(devices: [mouse(battery: 10)], enabled: true, threshold: 20)
        #expect(alerts.count == 1)
    }

    @Test("Toggling off clears history so next enable re-notifies")
    func toggleOffClearsHistory() {
        var tracker = BluetoothBatteryAlertTracker()
        _ = tracker.evaluate(devices: [mouse(battery: 10)], enabled: true, threshold: 20)

        let off = tracker.evaluate(devices: [mouse(battery: 10)], enabled: false, threshold: 20)
        #expect(off.isEmpty)

        let reEnabled = tracker.evaluate(devices: [mouse(battery: 10)], enabled: true, threshold: 20)
        #expect(reEnabled.count == 1)
    }

    @Test("Exact threshold value triggers (<=)")
    func exactThreshold() {
        var tracker = BluetoothBatteryAlertTracker()
        let alerts = tracker.evaluate(devices: [mouse(battery: 20)], enabled: true, threshold: 20)
        #expect(alerts.count == 1)
    }

    @Test("Device without any battery reading produces no alerts")
    func noBatteryNoAlert() {
        var tracker = BluetoothBatteryAlertTracker()
        let alerts = tracker.evaluate(devices: [mouse(battery: nil)], enabled: true, threshold: 20)
        #expect(alerts.isEmpty)
    }
}

// MARK: - BluetoothDeviceShapeTests

struct BluetoothDeviceShapeTests {

    @Test("hasAirPodsDetail true when any component populated")
    func detailTrue() {
        let device = BluetoothService.BluetoothDevice(
            id: "x", name: "AirPods Pro", category: .headphones,
            batteryLevel: 75, leftBattery: 70, rightBattery: nil, caseBattery: nil
        )
        #expect(device.hasAirPodsDetail)
    }

    @Test("hasAirPodsDetail false when only single battery present")
    func detailFalse() {
        let device = BluetoothService.BluetoothDevice(
            id: "x", name: "Magic Mouse", category: .mouse,
            batteryLevel: 50, leftBattery: nil, rightBattery: nil, caseBattery: nil
        )
        #expect(!device.hasAirPodsDetail)
    }
}
