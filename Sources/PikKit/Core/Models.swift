import Foundation

public enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case display, window, custom, cameraOnly
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .display: return t("Record display", "Grabar pantalla")
        case .window: return t("Record window", "Grabar ventana")
        case .custom: return t("Record custom size", "Grabar tamaño personalizado")
        case .cameraOnly: return t("Record camera only", "Grabar solo cámara")
        }
    }
    public var symbol: String {
        switch self {
        case .display: return "laptopcomputer"
        case .window: return "macwindow"
        case .custom: return "rectangle.dashed"
        case .cameraOnly: return "person.crop.rectangle"
        }
    }
}

public enum VideoResolution: String, Codable, CaseIterable, Identifiable {
    case p720 = "720p", p1080 = "1080p", p1440 = "1440p", k4 = "4K", native = "native"
    public var id: String { rawValue }
    public var title: String {
        self == .native ? t("Native", "Nativa") : rawValue
    }
    /// Alto máximo en píxeles (nil = sin límite).
    public var maxHeight: Int? {
        switch self {
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .k4: return 2160
        case .native: return nil
        }
    }
}

public enum PrivacyLevel: String, Codable, CaseIterable, Identifiable {
    case onlyMe, anyoneWithLink
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .onlyMe: return t("Only me", "Solo yo")
        case .anyoneWithLink: return t("Anyone with the link", "Cualquiera con el enlace")
        }
    }
    public var detail: String {
        switch self {
        case .onlyMe:
            return t("Only you will be able to view this video. You can share it later.",
                     "Solo vos podrás ver este video. Podés compartirlo después.")
        case .anyoneWithLink:
            return t("Anyone on your network with the link will be able to view this video.",
                     "Cualquiera en tu red con el enlace podrá ver este video.")
        }
    }
    public var symbol: String { self == .onlyMe ? "lock.fill" : "link" }
}

public enum AfterRecordingAction: String, Codable, CaseIterable, Identifiable {
    case openPreview, copyLink, copyFile, revealInFinder, nothing
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openPreview: return t("Open preview", "Abrir vista previa")
        case .copyLink: return t("Copy link", "Copiar enlace")
        case .copyFile: return t("Copy file", "Copiar archivo")
        case .revealInFinder: return t("Show in Finder", "Mostrar en Finder")
        case .nothing: return t("Do nothing", "No hacer nada")
        }
    }
}

public enum CameraShape: String, Codable, CaseIterable, Identifiable {
    case circle, roundedSquare
    public var id: String { rawValue }
    public var symbol: String { self == .circle ? "circle" : "square" }
}

public enum CameraEffect: String, Codable, CaseIterable, Identifiable {
    case none, blur, color, image
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return t("None", "Ninguno")
        case .blur: return t("Blurred background", "Fondo difuminado")
        case .color: return t("Solid color", "Color sólido")
        case .image: return t("Image", "Imagen")
        }
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return t("System", "Sistema")
        case .light: return t("Light", "Claro")
        case .dark: return t("Dark", "Oscuro")
        }
    }
}

public enum ItemKind: String, Codable, CaseIterable {
    case video, screenshot, meeting, dictation
}

/// Estado del flujo de grabación.
public enum RecordingPhase: Equatable {
    case idle
    case armed          // barra de controles abierta
    case countdown
    case recording
    case paused
    case finishing
}
