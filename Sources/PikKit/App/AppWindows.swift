import AppKit
import SwiftUI

public enum LibraryTab: String, CaseIterable, Identifiable {
    case videos, notes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .videos: return t("Videos", "Videos")
        case .notes: return t("Notes", "Notas")
        }
    }
    public var symbol: String {
        switch self {
        case .videos: return "play.rectangle.fill"
        case .notes: return "note.text"
        }
    }
}

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general, shortcuts, gestures, account, about
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: return t("General", "General")
        case .shortcuts: return t("Shortcuts", "Atajos")
        case .gestures: return t("Gestures", "Gestos")
        case .account: return t("Account", "Cuenta")
        case .about: return t("About", "Acerca de")
        }
    }
    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .gestures: return "hand.raised"
        case .account: return "person.crop.circle"
        case .about: return "info.circle"
        }
    }
}

/// Punto único para abrir las ventanas normales de Pik.
@MainActor
public enum AppWindows {
    public static func showLibrary(tab: LibraryTab = .videos) {
        LibraryNavigation.shared.tab = tab
        WindowManager.shared.show(id: "library", title: "Pik", size: CGSize(width: 1020, height: 680), minSize: CGSize(width: 760, height: 480)) {
            LibraryWindowView()
        }
    }

    public static func showPreview(_ id: UUID) {
        guard let item = LibraryStore.shared.item(id: id) else { return }
        let size = CGSize(width: 1120, height: 720)
        WindowManager.shared.show(id: "preview-\(id.uuidString)", title: item.title, size: size, minSize: CGSize(width: 720, height: 520), transparentTitle: false) {
            PreviewWindowView(itemID: id)
        }
    }

    public static func showSettings(tab: SettingsTab = .general) {
        SettingsNavigation.shared.tab = tab
        WindowManager.shared.show(id: "settings", title: t("Pik Settings", "Ajustes de Pik"), size: CGSize(width: 640, height: 560),
                                  minSize: CGSize(width: 560, height: 420)) {
            SettingsWindowView()
        }
    }

    public static func showOnboarding() {
        WindowManager.shared.show(id: "onboarding", title: t("Welcome to Pik", "Bienvenido a Pik"), size: CGSize(width: 760, height: 560),
                                  resizable: false) { OnboardingView() }
    }

    /// Pantalla para grabar (o volver a grabar) el gesto de una acción.
    public static func showGestureRecorder(action: GestureAction) {
        WindowManager.shared.close(id: "gesture-recorder")
        var window: NSWindow?
        window = WindowManager.shared.show(id: "gesture-recorder", title: t("Record gesture", "Grabar gesto"), size: CGSize(width: 520, height: 600),
                                           resizable: false, transparentTitle: false) {
            GestureRecorderView(action: action) { window?.close() }
        }
    }

    public static func showSetup() {
        WindowManager.shared.show(id: "setup", title: t("Set up Pik", "Configurar Pik"), size: CGSize(width: 520, height: 600), resizable: false) {
            SetupView()
        }
    }
}

public final class LibraryNavigation: ObservableObject {
    public static let shared = LibraryNavigation()
    @Published public var tab: LibraryTab = .videos
}

public final class SettingsNavigation: ObservableObject {
    public static let shared = SettingsNavigation()
    @Published public var tab: SettingsTab = .general
}
