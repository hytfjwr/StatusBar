import CoreAudio
import CoreMediaIO
import Foundation

final class MicCameraService: @unchecked Sendable {
    struct State: Sendable {
        var micActive: Bool
        var cameraActive: Bool
    }

    private let onChange: @Sendable (State) -> Void
    private let queue = DispatchQueue(label: "com.statusbar.miccamera")
    private var inputDeviceIDs: [AudioDeviceID] = []
    private var listenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListBlock: AudioObjectPropertyListenerBlock?

    // Camera
    private var cameraDeviceIDs: [CMIOObjectID] = []
    private var cameraListenerBlocks: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var cameraDeviceListBlock: CMIOObjectPropertyListenerBlock?

    init(onChange: @escaping @Sendable (State) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            setupMicListeners()
            installDeviceListListener()
            setupCameraListeners()
            installCameraDeviceListListener()
            let state = computeState()
            onChange(state)
        }
    }

    func stop() {
        queue.sync {
            removeDeviceListListener()
            removeMicListeners()
            removeCameraDeviceListListener()
            removeCameraListeners()
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

    /// Listen for device additions/removals (e.g. USB mic plug/unplug).
    /// Rebuilds per-device listeners when the device list changes.
    private func installDeviceListListener() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.removeMicListeners()
            self.setupMicListeners()
            let state = self.computeState()
            self.onChange(state)
        }
        deviceListBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddress, queue, block
        )
    }

    private func removeDeviceListListener() {
        guard let block = deviceListBlock else { return }
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddress, queue, block
        )
        deviceListBlock = nil
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

    // MARK: - Camera (CoreMediaIO)

    private func setupCameraListeners() {
        cameraDeviceIDs = allCameraDeviceIDs()
        for deviceID in cameraDeviceIDs {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                let state = self.computeState()
                self.onChange(state)
            }
            cameraListenerBlocks[deviceID] = block
            CMIOObjectAddPropertyListenerBlock(deviceID, &address, queue, block)
        }
    }

    private func removeCameraListeners() {
        for deviceID in cameraDeviceIDs {
            guard let block = cameraListenerBlocks[deviceID] else { continue }
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectRemovePropertyListenerBlock(deviceID, &address, queue, block)
        }
        cameraListenerBlocks = [:]
        cameraDeviceIDs = []
    }

    private func installCameraDeviceListListener() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.removeCameraListeners()
            self.setupCameraListeners()
            let state = self.computeState()
            self.onChange(state)
        }
        cameraDeviceListBlock = block
        CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &address, queue, block
        )
    }

    private func removeCameraDeviceListListener() {
        guard let block = cameraDeviceListBlock else { return }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectRemovePropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &address, queue, block
        )
        cameraDeviceListBlock = nil
    }

    private func allCameraDeviceIDs() -> [CMIOObjectID] {
        var size: UInt32 = 0
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var deviceIDs = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &dataUsed, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs
    }

    private func isCameraRunning(_ deviceID: CMIOObjectID) -> Bool {
        var running: UInt32 = 0
        var dataUsed: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &dataUsed, &running)
        return status == noErr && running != 0
    }

    // MARK: - State computation (called on queue)

    /// Compute current mic and camera state. Must be called on the serial queue.
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

        let cameraActive = cameraDeviceIDs.contains { isCameraRunning($0) }

        return State(micActive: micActive, cameraActive: cameraActive)
    }
}
