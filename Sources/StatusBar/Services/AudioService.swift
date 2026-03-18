import CoreAudio
import Foundation

final class AudioService: @unchecked Sendable {
    private let onChange: @Sendable (Int) -> Void
    private let queue = DispatchQueue(label: "com.statusbar.audio")

    // Protected by queue
    private var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var volumeElement: UInt32 = kAudioObjectPropertyElementMain
    private var listening = false
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?

    init(onChange: @escaping @Sendable (Int) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            setupListeners()
            let vol = getVolume()
            onChange(vol)
        }
    }

    func stop() {
        queue.sync {
            removeListeners()
        }
    }

    // MARK: - Setup / Teardown (called on queue)

    private func setupListeners() {
        // Listen for default output device changes (e.g. switching to AirPods)
        var deviceChangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceChangeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Callback dispatched on our serial queue, so direct access is safe
            guard let self else {
                return
            }
            removeDeviceListeners()
            setupDeviceListeners()
            let vol = getVolume()
            onChange(vol)
        }
        deviceChangeListenerBlock = deviceChangeBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceChangeAddress, queue, deviceChangeBlock
        )

        setupDeviceListeners()
    }

    private func setupDeviceListeners() {
        defaultDeviceID = getDefaultOutputDevice()
        guard defaultDeviceID != kAudioObjectUnknown else {
            return
        }

        volumeElement = findVolumeElement()

        // Listen for volume changes
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: volumeElement
        )

        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Callback dispatched on our serial queue
            guard let self else {
                return
            }
            let vol = getVolume()
            onChange(vol)
        }
        volumeListenerBlock = volumeBlock
        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &volumeAddress, queue, volumeBlock)

        // Listen for mute changes
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Callback dispatched on our serial queue
            guard let self else {
                return
            }
            let vol = getVolume()
            onChange(vol)
        }
        muteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &muteAddress, queue, muteBlock)

        listening = true
    }

    private func removeListeners() {
        removeDeviceListeners()

        if let block = deviceChangeListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            )
            deviceChangeListenerBlock = nil
        }
    }

    private func removeDeviceListeners() {
        guard listening, defaultDeviceID != kAudioObjectUnknown else {
            return
        }

        if let block = volumeListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: volumeElement
            )
            AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &address, queue, block)
        }

        if let block = muteListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &address, queue, block)
        }

        volumeListenerBlock = nil
        muteListenerBlock = nil
        listening = false
    }

    // MARK: - Volume / Mute Control

    func setVolume(_ percent: Int) {
        queue.async { [weak self] in
            guard let self, defaultDeviceID != kAudioObjectUnknown else {
                return
            }

            var volume = Float32(max(0, min(100, percent))) / 100.0
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: volumeElement
            )
            AudioObjectSetPropertyData(
                defaultDeviceID, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &volume
            )

            // Unmute when user explicitly sets volume > 0
            if percent > 0 {
                setMuteInternal(false)
            }
        }
    }

    func setMute(_ muted: Bool) {
        queue.async { [weak self] in
            guard let self, defaultDeviceID != kAudioObjectUnknown else {
                return
            }
            setMuteInternal(muted)
        }
    }

    func isMuted() -> Bool {
        // Use dispatchPrecondition to guard against deadlock if already on queue.
        // Since callbacks now fire on our queue, public callers must not be on queue.
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync {
            guard defaultDeviceID != kAudioObjectUnknown else {
                return false
            }
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &muted) == noErr {
                return muted == 1
            }
            return false
        }
    }

    /// Raw volume (0–100) ignoring mute state.
    func rawVolume() -> Int {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync {
            guard defaultDeviceID != kAudioObjectUnknown else {
                return 0
            }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: volumeElement
            )
            if AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &volume) == noErr {
                return Int(volume * 100)
            }
            return 0
        }
    }

    private func setMuteInternal(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            defaultDeviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value
        )
    }

    // MARK: - Private (called on queue)

    /// Find the element that has the volume scalar property.
    /// Many devices don't expose master volume (element 0) — only per-channel (element 1, 2).
    private func findVolumeElement() -> UInt32 {
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(defaultDeviceID, &address) {
                return element
            }
        }
        return kAudioObjectPropertyElementMain
    }

    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func getVolume() -> Int {
        guard defaultDeviceID != kAudioObjectUnknown else {
            return 0
        }

        // Check mute
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectGetPropertyData(defaultDeviceID, &muteAddress, 0, nil, &muteSize, &muted) == noErr,
           muted == 1
        {
            return 0
        }

        // Get volume using the detected element
        var volume: Float32 = 0
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: volumeElement
        )

        if AudioObjectGetPropertyData(defaultDeviceID, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr {
            return Int(volume * 100)
        }

        return 0
    }
}
