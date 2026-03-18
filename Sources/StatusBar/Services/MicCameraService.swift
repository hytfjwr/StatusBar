import CoreAudio
import Foundation

final class MicCameraService: @unchecked Sendable {
    struct State: Sendable {
        var micActive: Bool
    }

    private let onChange: @Sendable (State) -> Void
    private let queue = DispatchQueue(label: "com.statusbar.miccamera")
    private var inputDeviceIDs: [AudioDeviceID] = []
    private var listenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    init(onChange: @escaping @Sendable (State) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            setupMicListeners()
            let state = computeState()
            onChange(state)
        }
    }

    func stop() {
        queue.sync {
            removeMicListeners()
        }
    }

    // MARK: - Mic (CoreAudio)

    private func setupMicListeners() {
        inputDeviceIDs = allInputDeviceIDs()
        for deviceID in inputDeviceIDs {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                // Callback dispatched on our serial queue, so direct access is safe
                guard let self else { return }
                let state = self.computeState()
                self.onChange(state)
            }
            listenerBlocks[deviceID] = block
            AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block)
        }
    }

    private func removeMicListeners() {
        for deviceID in inputDeviceIDs {
            guard let block = listenerBlocks[deviceID] else { continue }
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, block)
        }
        listenerBlocks = [:]
        inputDeviceIDs = []
    }

    private func allInputDeviceIDs() -> [AudioDeviceID] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.filter { isInputDevice($0) }
    }

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 4)
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr) == noErr
        else { return false }

        let bufferList = bufferListPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        return bufferList.pointee.mNumberBuffers > 0
    }

    // MARK: - State computation (called on queue)

    /// Compute current mic state. Must be called on the serial queue.
    private func computeState() -> State {
        let micActive = inputDeviceIDs.contains { deviceID in
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
            return status == noErr && running != 0
        }
        return State(micActive: micActive)
    }
}
