@testable import StatusBar
import Testing

struct ProcessInfoServiceTests {

    // MARK: - parsePSOutput

    @Test("Parses multiple lines with leading whitespace padding")
    func parsesMultipleLines() {
        let output = """
              501   0.0   1234 /sbin/launchd
             4365  21.1 271600 /Applications/WezTerm.app/Contents/MacOS/wezterm-gui
        """
        let samples = ProcessInfoService.parsePSOutput(output)

        #expect(samples.count == 2)
        #expect(samples[0].pid == 501)
        #expect(samples[0].cpuPercent == 0.0)
        #expect(samples[0].residentBytes == 1_234 * 1_024)
        #expect(samples[0].name == "launchd")
        #expect(samples[1].pid == 4_365)
        #expect(samples[1].name == "wezterm-gui")
    }

    @Test("Extracts the last path component as name from a comm path containing spaces")
    func commWithSpacesInPath() {
        let output = "83459  31.9 284144 /Applications/Arc.app/Contents/Frameworks/ArcCore.framework/" +
            "Helpers/Browser Helper (Renderer).app/Contents/MacOS/Browser Helper (Renderer)"
        let samples = ProcessInfoService.parsePSOutput(output)

        #expect(samples.count == 1)
        #expect(samples[0].name == "Browser Helper (Renderer)")
    }

    @Test("Converts rss in KB to bytes")
    func rssToBytesConversion() {
        let output = "1  0.0  1024 /bin/sh"
        let samples = ProcessInfoService.parsePSOutput(output)

        #expect(samples.count == 1)
        #expect(samples[0].residentBytes == 1_048_576)
    }

    @Test("Skips malformed lines but keeps valid ones")
    func skipsMalformedLines() {
        let output = """
        1  0.0  1024 /bin/sh
        not-a-pid  0.0  1024 /bin/broken
        2  0.0
        3  1.5  2048 /bin/valid
        """
        let samples = ProcessInfoService.parsePSOutput(output)

        #expect(samples.count == 2)
        #expect(samples[0].pid == 1)
        #expect(samples[1].pid == 3)
    }

    @Test("Empty string returns an empty array")
    func emptyStringReturnsEmpty() {
        #expect(ProcessInfoService.parsePSOutput("").isEmpty)
    }

    // MARK: - topByCPU / topByMemory

    @Test("topByCPU sorts descending and applies the limit")
    func topByCPUSortsAndLimits() {
        let samples = [
            ProcessInfoService.ProcessSample(pid: 1, name: "a", cpuPercent: 10, residentBytes: 100),
            ProcessInfoService.ProcessSample(pid: 2, name: "b", cpuPercent: 50, residentBytes: 200),
            ProcessInfoService.ProcessSample(pid: 3, name: "c", cpuPercent: 30, residentBytes: 300),
        ]

        let top = ProcessInfoService.topByCPU(samples, limit: 2)

        #expect(top.map(\.pid) == [2, 3])
    }

    @Test("topByMemory sorts descending and applies the limit")
    func topByMemorySortsAndLimits() {
        let samples = [
            ProcessInfoService.ProcessSample(pid: 1, name: "a", cpuPercent: 10, residentBytes: 300),
            ProcessInfoService.ProcessSample(pid: 2, name: "b", cpuPercent: 50, residentBytes: 100),
            ProcessInfoService.ProcessSample(pid: 3, name: "c", cpuPercent: 30, residentBytes: 200),
        ]

        let top = ProcessInfoService.topByMemory(samples, limit: 2)

        #expect(top.map(\.pid) == [1, 3])
    }
}
