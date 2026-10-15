import AppKit
import AVFoundation
import CoreGraphics
import Speech

public enum PermissionKind: String, CaseIterable, Identifiable {
    case screen, camera, microphone, speech
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screen: return t("Screen recording", "Grabación de pantalla")
        case .camera: return t("Camera", "Cámara")
        case .microphone: return t("Microphone", "Micrófono")
        case .speech: return t("Speech recognition", "Reconocimiento de voz")
        }
    }
    public var detail: String {
        switch self {
        case .screen: return t("Needed to capture your screen, windows and custom areas.", "Necesario para capturar tu pantalla, ventanas y áreas.")
        case .camera: return t("Show yourself in a camera bubble or record camera only.", "Aparecé en una burbuja de cámara o grabá solo cámara.")
        case .microphone: return t("Record your voice with your videos.", "Grabá tu voz en tus videos.")
        case .speech: return t("Transcribe your recordings on your Mac and listen for “Pik”.", "Transcribir tus grabaciones en tu Mac y escuchar «Pik».")
        }
    }
    public var symbol: String {
        switch self {
        case .screen: return "rectangle.on.rectangle"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .speech: return "waveform"
        }
    }
    public var isRequired: Bool { self == .screen }
    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .screen: anchor = "Privacy_ScreenCapture"
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        case .speech: anchor = "Privacy_SpeechRecognition"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

public enum PermissionState { case granted, denied, notDetermined }

/// Chequea y pide permisos del sistema. Se actualiza solo (sondeo ligero) para la pantalla de configuración.
public final class Permissions: ObservableObject {
    public static let shared = Permissions()
    @Published public private(set) var states: [PermissionKind: PermissionState] = [:]
    private var timer: Timer?

    public init() { refresh() }

    public func state(_ k: PermissionKind) -> PermissionState { states[k] ?? .notDetermined }
    public func isGranted(_ k: PermissionKind) -> Bool { state(k) == .granted }

    public var allRequiredGranted: Bool { PermissionKind.allCases.filter(\.isRequired).allSatisfy(isGranted) }

    public func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
    }
    public func stopPolling() { timer?.invalidate(); timer = nil }

    public func refresh() {
        var s: [PermissionKind: PermissionState] = [:]
        s[.screen] = CGPreflightScreenCaptureAccess() ? .granted : .denied
        s[.camera] = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        s[.microphone] = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: s[.speech] = .granted
        case .notDetermined: s[.speech] = .notDetermined
        default: s[.speech] = .denied
        }
        if states != s { states = s }
    }

    private static func map(_ s: AVAuthorizationStatus) -> PermissionState {
        switch s {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Pide el permiso (muestra el diálogo del sistema si todavía no se decidió) o abre Ajustes.
    public func request(_ k: PermissionKind) {
        switch k {
        case .screen:
            if CGPreflightScreenCaptureAccess() { return }
            // Si el usuario ya lo rechazó, el diálogo no vuelve a salir: abrimos Ajustes.
            let asked = UserDefaults.standard.bool(forKey: "askedScreenCapture")
            if !asked {
                UserDefaults.standard.set(true, forKey: "askedScreenCapture")
                _ = CGRequestScreenCaptureAccess()
            } else {
                openSettings(k)
            }
        case .camera:
            if state(k) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            } else { openSettings(k) }
        case .microphone:
            if state(k) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            } else { openSettings(k) }
        case .speech:
            if state(k) == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            } else { openSettings(k) }
        }
    }

    public func openSettings(_ k: PermissionKind) {
        NSWorkspace.shared.open(k.settingsURL)
    }

    /// Pide cámara/micro y avisa cuando hay respuesta.
    public func ensure(_ k: PermissionKind, completion: @escaping (Bool) -> Void) {
        refresh()
        if isGranted(k) { completion(true); return }
        switch k {
        case .camera where state(k) == .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { self.refresh(); completion(ok) } }
        case .microphone where state(k) == .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { self.refresh(); completion(ok) } }
        case .speech where state(k) == .notDetermined:
            SFSpeechRecognizer.requestAuthorization { st in DispatchQueue.main.async { self.refresh(); completion(st == .authorized) } }
        default:
            completion(false)
        }
    }
}
