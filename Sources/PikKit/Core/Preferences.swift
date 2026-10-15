import Foundation
import SwiftUI
import Combine

/// Preferencias de usuario (UserDefaults) observables desde SwiftUI.
public final class Preferences: ObservableObject {
    public static let shared: Preferences = {
        if let suite = ProcessInfo.processInfo.environment["PIK_DEFAULTS_SUITE"], let d = UserDefaults(suiteName: suite) { return Preferences(defaults: d) }
        return Preferences()
    }()
    private let d: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        d = defaults
        language = defaults.string(forKey: "language") ?? "system"
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        alwaysShowInDock = defaults.bool(forKey: "alwaysShowInDock")
        openControlsOnActivate = defaults.object(forKey: "openControlsOnActivate") as? Bool ?? true
        videoSounds = defaults.object(forKey: "videoSounds") as? Bool ?? true
        voiceActivation = defaults.bool(forKey: "voiceActivation")
        gestureControl = defaults.bool(forKey: "gestureControl")
        gestureSensitivity = defaults.object(forKey: "gestureSensitivity") as? Double ?? 1.0
        noiseSuppression = defaults.object(forKey: "noiseSuppression") as? Bool ?? true
        afterRecording = AfterRecordingAction(rawValue: defaults.string(forKey: "afterRecording") ?? "") ?? .openPreview
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? true
        hideSystemUI = defaults.object(forKey: "hideSystemUI") as? Bool ?? true
        hideDesktopIcons = defaults.object(forKey: "hideDesktopIcons") as? Bool ?? true
        highlightClicks = defaults.bool(forKey: "highlightClicks")
        includeSystemAudio = defaults.bool(forKey: "includeSystemAudio")
        resolution = VideoResolution(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .p1080
        fps = defaults.object(forKey: "fps") as? Int ?? 30
        useHEVC = defaults.bool(forKey: "useHEVC")
        mode = RecordingMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .display
        cameraEnabled = defaults.bool(forKey: "cameraEnabled")
        cameraDeviceID = defaults.string(forKey: "cameraDeviceID")
        micEnabled = defaults.object(forKey: "micEnabled") as? Bool ?? true
        micDeviceID = defaults.string(forKey: "micDeviceID")
        cameraShape = CameraShape(rawValue: defaults.string(forKey: "cameraShape") ?? "") ?? .circle
        cameraSize = defaults.object(forKey: "cameraSize") as? Double ?? 220
        cameraMirror = defaults.object(forKey: "cameraMirror") as? Bool ?? true
        cameraEffect = CameraEffect(rawValue: defaults.string(forKey: "cameraEffect") ?? "") ?? .none
        cameraEffectColorHex = defaults.string(forKey: "cameraEffectColorHex") ?? "#FF7A1A"
        cameraEffectImageID = defaults.string(forKey: "cameraEffectImageID")
        recordingBackgroundID = defaults.string(forKey: "recordingBackgroundID")
        defaultPrivacy = PrivacyLevel(rawValue: defaults.string(forKey: "defaultPrivacy") ?? "") ?? .onlyMe
        showNotes = defaults.bool(forKey: "showNotes")
        teleprompterSpeed = defaults.object(forKey: "teleprompterSpeed") as? Double ?? 28
        sharingEnabled = defaults.object(forKey: "sharingEnabled") as? Bool ?? true
        sharePort = defaults.object(forKey: "sharePort") as? Int ?? 8420
        libraryFolderPath = defaults.string(forKey: "libraryFolderPath")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        hasSeenCoachMarks = defaults.bool(forKey: "hasSeenCoachMarks")
        userName = defaults.string(forKey: "userName") ?? NSFullUserName()
        transcriptionLanguage = defaults.string(forKey: "transcriptionLanguage") ?? "auto"
        autoTranscribe = defaults.object(forKey: "autoTranscribe") as? Bool ?? true
        L10n.override = language == "system" ? nil : language
    }

    @Published public var language: String { didSet { d.set(language, forKey: "language"); L10n.override = language == "system" ? nil : language } }
    @Published public var appearance: AppearanceMode { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published public var alwaysShowInDock: Bool { didSet { d.set(alwaysShowInDock, forKey: "alwaysShowInDock") } }
    @Published public var openControlsOnActivate: Bool { didSet { d.set(openControlsOnActivate, forKey: "openControlsOnActivate") } }
    @Published public var videoSounds: Bool { didSet { d.set(videoSounds, forKey: "videoSounds") } }
    @Published public var gestureControl: Bool { didSet { d.set(gestureControl, forKey: "gestureControl") } }
    @Published public var gestureSensitivity: Double { didSet { d.set(gestureSensitivity, forKey: "gestureSensitivity") } }
    @Published public var voiceActivation: Bool { didSet { d.set(voiceActivation, forKey: "voiceActivation") } }
    @Published public var noiseSuppression: Bool { didSet { d.set(noiseSuppression, forKey: "noiseSuppression") } }
    @Published public var afterRecording: AfterRecordingAction { didSet { d.set(afterRecording.rawValue, forKey: "afterRecording") } }
    @Published public var showCountdown: Bool { didSet { d.set(showCountdown, forKey: "showCountdown") } }
    @Published public var hideSystemUI: Bool { didSet { d.set(hideSystemUI, forKey: "hideSystemUI") } }
    @Published public var hideDesktopIcons: Bool { didSet { d.set(hideDesktopIcons, forKey: "hideDesktopIcons") } }
    @Published public var highlightClicks: Bool { didSet { d.set(highlightClicks, forKey: "highlightClicks") } }
    @Published public var includeSystemAudio: Bool { didSet { d.set(includeSystemAudio, forKey: "includeSystemAudio") } }
    @Published public var resolution: VideoResolution { didSet { d.set(resolution.rawValue, forKey: "resolution") } }
    @Published public var fps: Int { didSet { d.set(fps, forKey: "fps") } }
    @Published public var useHEVC: Bool { didSet { d.set(useHEVC, forKey: "useHEVC") } }
    @Published public var mode: RecordingMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    @Published public var cameraEnabled: Bool { didSet { d.set(cameraEnabled, forKey: "cameraEnabled") } }
    @Published public var cameraDeviceID: String? { didSet { d.set(cameraDeviceID, forKey: "cameraDeviceID") } }
    @Published public var micEnabled: Bool { didSet { d.set(micEnabled, forKey: "micEnabled") } }
    @Published public var micDeviceID: String? { didSet { d.set(micDeviceID, forKey: "micDeviceID") } }
    @Published public var cameraShape: CameraShape { didSet { d.set(cameraShape.rawValue, forKey: "cameraShape") } }
    @Published public var cameraSize: Double { didSet { d.set(cameraSize, forKey: "cameraSize") } }
    @Published public var cameraMirror: Bool { didSet { d.set(cameraMirror, forKey: "cameraMirror") } }
    @Published public var cameraEffect: CameraEffect { didSet { d.set(cameraEffect.rawValue, forKey: "cameraEffect") } }
    @Published public var cameraEffectColorHex: String { didSet { d.set(cameraEffectColorHex, forKey: "cameraEffectColorHex") } }
    @Published public var cameraEffectImageID: String? { didSet { d.set(cameraEffectImageID, forKey: "cameraEffectImageID") } }
    @Published public var recordingBackgroundID: String? { didSet { d.set(recordingBackgroundID, forKey: "recordingBackgroundID") } }
    @Published public var defaultPrivacy: PrivacyLevel { didSet { d.set(defaultPrivacy.rawValue, forKey: "defaultPrivacy") } }
    @Published public var showNotes: Bool { didSet { d.set(showNotes, forKey: "showNotes") } }
    @Published public var teleprompterSpeed: Double { didSet { d.set(teleprompterSpeed, forKey: "teleprompterSpeed") } }
    @Published public var sharingEnabled: Bool { didSet { d.set(sharingEnabled, forKey: "sharingEnabled") } }
    @Published public var sharePort: Int { didSet { d.set(sharePort, forKey: "sharePort") } }
    @Published public var libraryFolderPath: String? { didSet { d.set(libraryFolderPath, forKey: "libraryFolderPath") } }
    @Published public var hasCompletedOnboarding: Bool { didSet { d.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    @Published public var hasSeenCoachMarks: Bool { didSet { d.set(hasSeenCoachMarks, forKey: "hasSeenCoachMarks") } }
    @Published public var userName: String { didSet { d.set(userName, forKey: "userName") } }
    /// Idioma de la transcripción de grabaciones: "auto" (detecta español o inglés), "es" o "en".
    @Published public var transcriptionLanguage: String { didSet { d.set(transcriptionLanguage, forKey: "transcriptionLanguage") } }
    @Published public var autoTranscribe: Bool { didSet { d.set(autoTranscribe, forKey: "autoTranscribe") } }

    public var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
