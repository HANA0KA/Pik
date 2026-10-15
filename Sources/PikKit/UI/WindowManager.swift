import AppKit
import Combine
import SwiftUI

/// Ventanas "normales" de Pik (biblioteca, ajustes, vista previa…). Mantiene el ícono del Dock mientras haya alguna abierta.
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()
    private var windows: [String: NSWindow] = [:]
    private var tokens: [NSObjectProtocol] = []

    public override init() {
        super.init()
        let prefsChange = Preferences.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateDockPolicy() }
        }
        cancellables.append(prefsChange)
    }
    private var cancellables: [Any] = []

    /// Muestra (o trae al frente) una ventana identificada por `id`.
    @discardableResult
    public func show<Content: View>(id: String, title: String, size: CGSize, minSize: CGSize? = nil,
                                    resizable: Bool = true, transparentTitle: Bool = true,
                                    @ViewBuilder content: () -> Content) -> NSWindow {
        if let w = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return w
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        if transparentTitle { style.insert(.fullSizeContentView) }
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = transparentTitle
        if transparentTitle { w.titleVisibility = .hidden }
        w.contentView = NSHostingView(rootView: LanguageRoot(content: content()).environmentObject(Preferences.shared))
        if let m = minSize { w.contentMinSize = m }
        w.center()
        w.delegate = self
        w.identifier = NSUserInterfaceItemIdentifier(id)
        windows[id] = w
        updateDockPolicy()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    public func window(id: String) -> NSWindow? { windows[id] }
    public func isOpen(_ id: String) -> Bool { windows[id]?.isVisible == true }

    public func close(id: String) { windows[id]?.close() }

    public func closeAll() { windows.values.forEach { $0.close() } }

    public var anyWindowOpen: Bool { windows.values.contains { $0.isVisible } }

    public func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let id = w.identifier?.rawValue else { return }
        windows[id] = nil
        DispatchQueue.main.async { self.updateDockPolicy() }
    }

    /// "Siempre mostrar en el Dock" o solo mientras haya ventanas abiertas.
    public func updateDockPolicy() {
        let wantRegular = Preferences.shared.alwaysShowInDock || anyWindowOpen
        let target: NSApplication.ActivationPolicy = wantRegular ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
            if target == .regular { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}


/// Reconstruye el contenido de la ventana al cambiar el idioma de la app, para que se traduzca al instante.
struct LanguageRoot<Content: View>: View {
    let content: Content
    @ObservedObject private var prefs = Preferences.shared
    var body: some View { content.id(prefs.language) }
}
