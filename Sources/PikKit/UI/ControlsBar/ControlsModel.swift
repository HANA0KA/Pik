import AppKit
import Combine
import Foundation

/// Estado y acciones de la barra de controles previa a grabar.
public final class ControlsModel: ObservableObject {
    public enum Popover: Equatable { case camera, mic, privacy, more }
    public enum MorePage { case menu, settings, backgrounds }

    @Published public var popover: Popover?
    @Published public var morePage: MorePage = .menu
    @Published public var isStarting = false
    @Published public var selectionText: String?     // p. ej. "1280 × 720" o nombre de la ventana

    public var onClose: () -> Void = {}
    public var onRecord: () -> Void = {}
    public var onModeChange: (RecordingMode) -> Void = { _ in }
    public var onToggleNotes: () -> Void = {}
    public var onOpenSettings: () -> Void = {}
    public var onCameraToggled: (Bool) -> Void = { _ in }

    public init() {}

    public func toggle(_ p: Popover) {
        if popover == p { popover = nil } else { popover = p; morePage = .menu }
    }
}
