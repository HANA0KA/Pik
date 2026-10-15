import AppKit
import Carbon.HIToolbox
import Combine

/// Ícono en la barra de menús: grabar, capturas, dictado, reuniones, recientes, biblioteca y ajustes.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var bag = Set<AnyCancellable>()
    private let coordinator = AppCoordinator.shared
    private let prefs = Preferences.shared
    private lazy var templateImage: NSImage = {
        let img = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Pik") ?? NSImage()
        img.isTemplate = true
        img.size = NSSize(width: 20, height: 20)
        return img
    }()

    public override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.toolTip = "Pik"
        updateButton()
        Publishers.CombineLatest(coordinator.$phase, coordinator.$elapsed)
            .receive(on: DispatchQueue.main).sink { [weak self] _, _ in self?.updateButton() }.store(in: &bag)
        NotificationCenter.default.publisher(for: ShortcutManager.didChange).sink { [weak self] _ in _ = self }.store(in: &bag)
    }

    public var isVisible: Bool { item.button?.window?.occlusionState.contains(.visible) ?? false }

    // MARK: Botón

    private func updateButton() {
        guard let b = item.button else { return }
        switch coordinator.phase {
        case .recording, .paused, .finishing:
            let paused = coordinator.phase == .paused
            let cfg = NSImage.SymbolConfiguration(paletteColors: [paused ? .systemYellow : .systemRed])
            let img = NSImage(systemSymbolName: paused ? "pause.circle.fill" : "record.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            b.image = img
            b.imagePosition = .imageLeft
            b.attributedTitle = NSAttributedString(string: " " + Fmt.duration(coordinator.elapsed),
                                                   attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        default:
            b.image = templateImage
            b.imagePosition = .imageOnly
            b.title = ""
            b.attributedTitle = NSAttributedString(string: "")
        }
    }

    // MARK: Menú

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch coordinator.phase {
        case .recording, .paused: buildRecordingMenu(menu)
        case .finishing, .countdown:
            add(menu, t("Starting…", "Iniciando…"), enabled: false)
            if coordinator.phase == .countdown { add(menu, t("Cancel", "Cancelar"), symbol: "xmark") { [weak self] in self?.coordinator.cancelCurrent() } }
        default: buildIdleMenu(menu)
        }
    }

    private func buildRecordingMenu(_ menu: NSMenu) {
        let paused = coordinator.phase == .paused
        add(menu, (paused ? t("Paused", "En pausa") : t("Recording", "Grabando")) + " – " + Fmt.duration(coordinator.elapsed), enabled: false)
        menu.addItem(.separator())
        add(menu, t("Stop recording", "Detener grabación"), symbol: "stop.circle.fill", action: .startStop) { [weak self] in self?.coordinator.stopRecording() }
        add(menu, paused ? t("Resume", "Reanudar") : t("Pause", "Pausar"), symbol: paused ? "play.fill" : "pause.fill", action: .pauseResume) { [weak self] in self?.coordinator.togglePause() }
        add(menu, t("Delete recording", "Eliminar grabación"), symbol: "trash", action: .cancelRecording) { [weak self] in self?.coordinator.cancelCurrent() }
    }

    private func buildIdleMenu(_ menu: NSMenu) {
        let lib = add(menu, t("Library", "Biblioteca"), symbol: "square.grid.2x2.fill") { AppWindows.showLibrary() }
        lib.keyEquivalent = "l"; lib.keyEquivalentModifierMask = .command
        add(menu, t("Notes", "Notas"), symbol: "note.text") { AppWindows.showLibrary(tab: .notes) }
        menu.addItem(.separator())
        for m in RecordingMode.allCases {
            add(menu, m.title, symbol: m.symbol, action: m == .display ? .openControls : nil) { [weak self] in self?.coordinator.openControls(mode: m) }
        }
        menu.addItem(.separator())

        let recents = LibraryStore.shared.items(of: [.video, .meeting]).prefix(5)
        if !recents.isEmpty {
            add(menu, t("Recent recordings", "Grabaciones recientes"), enabled: false)
            for e in recents {
                let it = add(menu, "\(e.title)  ·  \(Fmt.duration(e.duration))", symbol: "play.rectangle") { AppWindows.showPreview(e.id) }
                it.indentationLevel = 1
            }
        }
        if !recents.isEmpty { menu.addItem(.separator()) }

        let settings = add(menu, t("Settings…", "Ajustes…"), symbol: "gearshape") { AppWindows.showSettings() }
        settings.keyEquivalent = ","; settings.keyEquivalentModifierMask = .command
        if !Permissions.shared.allRequiredGranted {
            add(menu, t("Grant permissions…", "Dar permisos…"), symbol: "exclamationmark.triangle.fill") { AppWindows.showSetup() }
        }
        menu.addItem(.separator())
        let quit = add(menu, t("Quit Pik", "Salir de Pik"), symbol: nil) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"; quit.keyEquivalentModifierMask = .command
    }

    // MARK: Helpers

    private func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return img
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, symbol sym: String? = nil, enabled: Bool = true,
                     action shortcutAction: ShortcutAction? = nil, handler: (() -> Void)? = nil) -> NSMenuItem {
        let it = ClosureMenuItem(title: title, handler: handler)
        it.isEnabled = enabled && handler != nil
        if let sym { it.image = symbol(sym) }
        if let a = shortcutAction, let s = ShortcutManager.shared.shortcut(for: a) {
            let key = Shortcut.keyName(s.keyCode)
            if key.count == 1 {
                it.keyEquivalent = key.lowercased()
                var m: NSEvent.ModifierFlags = []
                if s.modifiers & UInt32(controlKey) != 0 { m.insert(.control) }
                if s.modifiers & UInt32(optionKey) != 0 { m.insert(.option) }
                if s.modifiers & UInt32(shiftKey) != 0 { m.insert(.shift) }
                if s.modifiers & UInt32(cmdKey) != 0 { m.insert(.command) }
                it.keyEquivalentModifierMask = m
            }
        }
        menu.addItem(it)
        return it
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?
    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler?() }
}
