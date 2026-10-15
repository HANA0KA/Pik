import AVFoundation
import Foundation

public struct DeviceInfo: Identifiable, Hashable {
    public let id: String      // uniqueID
    public let name: String
}

public enum DeviceCatalog {
    public static func cameras() -> [DeviceInfo] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices.map { DeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    public static func microphones() -> [DeviceInfo] {
        let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
            .devices.map { DeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    public static func camera(id: String?) -> AVCaptureDevice? {
        if let id, let d = AVCaptureDevice(uniqueID: id) { return d }
        return AVCaptureDevice.default(for: .video) ?? AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices.first
    }

    public static func microphone(id: String?) -> AVCaptureDevice? {
        if let id, let d = AVCaptureDevice(uniqueID: id) { return d }
        return AVCaptureDevice.default(for: .audio)
    }
}

/// Avisa a la UI cuando se conecta o desconecta una cámara/micrófono.
public final class DeviceMonitor: ObservableObject {
    public static let shared = DeviceMonitor()
    @Published public private(set) var cameras: [DeviceInfo] = DeviceCatalog.cameras()
    @Published public private(set) var microphones: [DeviceInfo] = DeviceCatalog.microphones()
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
    }

    public func refresh() {
        cameras = DeviceCatalog.cameras()
        microphones = DeviceCatalog.microphones()
    }
}
