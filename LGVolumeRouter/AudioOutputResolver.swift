import CoreAudio
import Foundation

/// Reads the macOS default output device and enumerates output-capable devices.
/// "Which device should the volume keys control" is defined by macOS as the
/// default output device — the thing the user is actually hearing.
final class AudioOutputResolver {
    /// Identity of the current default output device, if any.
    func currentDefaultOutput() -> AudioOutputDevice? {
        guard let deviceID = Self.defaultOutputDeviceID() else { return nil }
        return Self.identity(for: deviceID)
    }

    /// Output-capable devices for the configuration window.
    func outputDevices() -> [AudioOutputDevice] {
        Self.allDeviceIDs()
            .filter(Self.hasOutputChannels)
            .compactMap(Self.identity(for:))
    }

    // MARK: - CoreAudio property helpers

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = defaultOutputAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return false
        }
        // Apple's documented kAudioDevicePropertyStreamConfiguration pattern:
        // the property writes one AudioBuffer per output stream, so allocate
        // exactly the reported `size` bytes. A fixed-capacity list would
        // overflow for multi-stream devices.
        let rawBuffer = malloc(Int(size))
        guard let rawBuffer else { return false }
        defer { free(rawBuffer) }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawBuffer) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(
            rawBuffer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private static func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    static func identity(for deviceID: AudioDeviceID) -> AudioOutputDevice? {
        let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID)
            ?? stringProperty(kAudioDevicePropertyDeviceNameCFString, deviceID: deviceID)
        guard let name else { return nil }
        return AudioOutputDevice(
            uid: stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID) ?? "",
            name: name,
            isAirPlay: transportType(for: deviceID) == kAudioDeviceTransportTypeAirPlay
        )
    }
}
