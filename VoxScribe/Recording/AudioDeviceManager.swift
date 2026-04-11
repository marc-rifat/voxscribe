import CoreAudio
import Foundation

/// Represents an audio input device available on the system.
struct AudioInputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

/// Enumerates and monitors available audio input devices via CoreAudio.
///
/// Publishes changes to the device list when devices are connected or
/// disconnected, allowing the UI to update dynamically.
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        installDeviceChangeListener()
    }

    /// Returns the system default input device ID, or nil if unavailable.
    ///
    /// - Returns: The `AudioDeviceID` of the default input device.
    var defaultInputDeviceID: AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Refreshes the list of available audio input devices.
    func refreshDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        let devices = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard hasInputChannels(deviceID) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            let uid = deviceUID(deviceID) ?? "\(deviceID)"
            return AudioInputDevice(id: deviceID, name: name, uid: uid)
        }

        DispatchQueue.main.async {
            self.inputDevices = devices
        }
    }

    /// Checks whether a device has input channels.
    ///
    /// - Parameter deviceID: The CoreAudio device ID to check.
    /// - Returns: `true` if the device has at least one input channel.
    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        let getStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, bufferListPointer
        )
        guard getStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    /// Returns the display name of a CoreAudio device.
    ///
    /// - Parameter deviceID: The device to query.
    /// - Returns: The device name string, or nil on failure.
    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    /// Returns the unique identifier string for a CoreAudio device.
    ///
    /// - Parameter deviceID: The device to query.
    /// - Returns: The device UID string, or nil on failure.
    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr else { return nil }
        return uid as String
    }

    /// Installs a listener for device connection/disconnection changes.
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    deinit {
        if let block = listenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
}
