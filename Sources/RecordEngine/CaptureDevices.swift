import Foundation
import AVFoundation
import GrabiDomain

/// Cameras and microphones available right now. Grabi lists what exists
/// instead of assuming the built-in one: people record with external
/// webcams, Continuity Camera and USB mics.
public enum CaptureDevices {
    public static func cameras() -> [CaptureDeviceInfo] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) { types.append(.continuityCamera) }
        return devices(types: types, mediaType: .video)
    }

    public static func microphones() -> [CaptureDeviceInfo] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone]
        if #available(macOS 14.0, *) { types.append(.external) }
        return devices(types: types, mediaType: .audio)
    }

    private static func devices(types: [AVCaptureDevice.DeviceType],
                                mediaType: AVMediaType) -> [CaptureDeviceInfo] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: mediaType, position: .unspecified)
        let defaultID = AVCaptureDevice.default(for: mediaType)?.uniqueID
        var seen = Set<String>()
        return session.devices.compactMap { device in
            guard seen.insert(device.uniqueID).inserted else { return nil }
            return CaptureDeviceInfo(id: device.uniqueID,
                                     name: device.localizedName,
                                     isSystemDefault: device.uniqueID == defaultID)
        }
    }

    /// Name to show for a stored id: the device if it is still connected,
    /// otherwise nil so the caller can fall back to "system default".
    public static func name(forCamera id: String?) -> String? {
        guard let id else { return nil }
        return cameras().first { $0.id == id }?.name
    }

    public static func name(forMicrophone id: String?) -> String? {
        guard let id else { return nil }
        return microphones().first { $0.id == id }?.name
    }
}
