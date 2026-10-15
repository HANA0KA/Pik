import AppKit
import Combine

/// Delegado de la app: arranque, atajos globales, esquema pik://, menú principal y cierre seguro.
@MainActor
public final class PikAppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController?
    private var bag = Set<AnyCancellable>()
    private let prefs = Preferences.shared
    private let coordinator = AppCoordinator.shared

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        plog("Pik \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") arrancó")
        NSApp.setActivationPolicy(prefs.alwaysShowInDock ? .regular : .accessory)
        installMainMenu()
        applyAppearance()
        prefs.$appearance.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.applyAppearance() }.store(in: &bag)

        status = StatusItemController()
        setUpVoiceActivation()
        setUpGestures()
        installShortcuts()
        startShareServer()

        _ = LaunchState.screenAtLaunch
        Permissions.shared.startPolling()
        Task { await recoverRecordings() }

        if !prefs.hasCompletedOnboarding {
            AppWindows.showOnboarding()
        } else if !Permissions.shared.allRequiredGranted {
            AppWindows.showSetup()
        } else if prefs.openControlsOnActivate {
            // Al abrir Pik aparece la barra de grabación (no solo el ícono de la barra de menús).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.coordinator.isBusy == false { self?.coordinator.openControls() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.warnIfIconHidden() }
    }

    /// Gestos de mano opcionales (cámara + Vision): iniciar, pausar/reanudar y detener con los gestos que grabó el usuario.
    private func setUpGestures() {
        let controller = GestureController.shared
        controller.onAction = { [weak self] action in
            guard let self else { return }
            ToastPresenter.shared.show(title: action.title, symbol: action.symbol, duration: 1.5)
            self.coordinator.performGesture(action)
        }
        let sync: () -> Void = { [weak self] in
            guard let self else { return }
            controller.update(templates: GestureStore.shared.templates, sensitivity: self.prefs.gestureSensitivity)
            controller.setEnabled(self.prefs.gestureControl)
        }
        prefs.$gestureControl.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] on in
            guard on else { sync(); return }
            Permissions.shared.ensure(.camera) { ok in
                if ok { sync() } else {
                    self?.prefs.gestureControl = false
                    ToastPresenter.shared.show(title: t("Allow camera access to use gestures", "Permití la cámara para usar gestos"), symbol: "video.slash", duration: 5)
                }
            }
        }.store(in: &bag)
        prefs.$gestureSensitivity.dropFirst().receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &bag)
        GestureStore.shared.$templates.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &bag)
        coordinator.$phase.receive(on: DispatchQueue.main).sink { controller.update(phase: $0) }.store(in: &bag)
        DispatchQueue.main.async { sync() }
    }

    /// Activación por voz opcional: escucha con Pik en reposo o con la barra abierta, y se calla al empezar la cuenta regresiva o la grabación.
    private func setUpVoiceActivation() {
        guard #available(macOS 26.0, *) else { return }
        VoiceActivation.shared.onWake = { [weak self] in
            guard let self, self.coordinator.phase == .idle || self.coordinator.phase == .armed else { return }
            plog("Activación por voz: «Pik» detectado")
            ToastPresenter.shared.show(title: t("Heard “Pik”", "Escuché «Pik»"), symbol: "waveform", duration: 2)
            self.coordinator.startFromVoice()
        }
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            let phase = self.coordinator.phase
            let should = self.prefs.voiceActivation && (phase == .idle || phase == .armed)   // también con la barra abierta; no durante cuenta regresiva ni grabación
            if should { VoiceActivation.shared.start() } else { VoiceActivation.shared.stop() }
        }
        prefs.$voiceActivation.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] on in
            guard on else { update(); return }
            Permissions.shared.ensure(.microphone) { ok in
                if ok { update() } else {
                    self?.prefs.voiceActivation = false
                    ToastPresenter.shared.show(title: t("Allow microphone access to use voice activation", "Permití el micrófono para usar la activación por voz"), symbol: "mic.slash", duration: 5)
                }
            }
        }.store(in: &bag)
        coordinator.$phase.receive(on: DispatchQueue.main).sink { _ in update() }.store(in: &bag)
        DispatchQueue.main.async { update() }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.isRecording else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = t("You're recording", "Estás grabando")
        alert.informativeText = t("Stop the recording, save it and quit Pik?", "¿Detener la grabación, guardarla y salir de Pik?")
        alert.addButton(withTitle: t("Stop and quit", "Detener y salir"))
        alert.addButton(withTitle: t("Keep recording", "Seguir grabando"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        coordinator.stopRecording()
        Task {
            while coordinator.phase != .idle { try? await Task.sleep(nanoseconds: 100_000_000) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        LibraryStore.shared.flush()
        ShortcutManager.shared.unregisterAll()
        ShareServer.shared.stop()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if prefs.openControlsOnActivate, !coordinator.isBusy { coordinator.openControls() }
        else if !flag, !coordinator.isBusy { AppWindows.showLibrary() }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle(url:))
    }

    // MARK: pik://

    /// pik://record[/display|window|custom|camera]  pik://stop  pik://pause  pik://library  pik://settings
    /// pik://preview/<id>
    public func handle(url: URL) {
        guard url.scheme == "pik" else { return }
        let host = url.host ?? ""
        let sub = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "record":
            let mode: RecordingMode? = ["display": .display, "window": .window, "custom": .custom, "camera": .cameraOnly][sub]
            coordinator.openControls(mode: mode)
        case "stop": coordinator.stopRecording()
        case "pause": coordinator.togglePause()
        case "library": AppWindows.showLibrary(tab: LibraryTab(rawValue: sub) ?? .videos)
        case "settings": AppWindows.showSettings(tab: SettingsTab(rawValue: sub) ?? .general)
        case "preview": if let id = UUID(uuidString: sub) { AppWindows.showPreview(id) }
        default: AppWindows.showLibrary()
        }
    }

    // MARK: Piezas

    private func installShortcuts() {
        let m = ShortcutManager.shared
        m.handlers = [
            .openControls: { [weak self] in self?.coordinator.toggleControls() },
            .startStop: { [weak self] in self?.coordinator.startOrStop() },
            .pauseResume: { [weak self] in self?.coordinator.togglePause() },
            .cancelRecording: { [weak self] in self?.coordinator.cancelCurrent() },
        ]
        m.registerAll()
    }

    private func startShareServer() {
        func sync() {
            if prefs.sharingEnabled { _ = ShareServer.shared.start(preferredPort: prefs.sharePort) } else { ShareServer.shared.stop() }
        }
        sync()
        prefs.$sharingEnabled.dropFirst().receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &bag)
        prefs.$sharePort.dropFirst().debounce(for: .milliseconds(600), scheduler: DispatchQueue.main).sink { _ in sync() }.store(in: &bag)
    }

    private func recoverRecordings() async {
        let recovered = await LibraryStore.shared.recoverInterrupted()
        guard !recovered.isEmpty else { return }
        ToastPresenter.shared.show(
            title: recovered.count == 1 ? t("Recording recovered", "Grabación recuperada") : t("\(recovered.count) recordings recovered", "\(recovered.count) grabaciones recuperadas"),
            subtitle: t("Pik closed unexpectedly. What was captured is in your library.", "Pik se cerró de forma inesperada. Lo capturado está en tu biblioteca."),
            symbol: "arrow.counterclockwise.circle.fill",
            actions: [ToastAction(t("Open library", "Abrir biblioteca")) { AppWindows.showLibrary() }], duration: 10)
    }

    private func warnIfIconHidden() {
        guard let status, !status.isVisible, prefs.hasCompletedOnboarding else { return }
        let sc = ShortcutManager.shared.shortcut(for: .openControls)?.display ?? ""
        ToastPresenter.shared.show(title: t("Pik's menu bar icon is hidden", "El ícono de Pik está oculto"),
                                   subtitle: t("Your menu bar is full or the notch is covering it. Use \(sc) or the Dock.", "La barra de menús está llena o el notch lo tapa. Usá \(sc) o el Dock."),
                                   symbol: "menubar.rectangle",
                                   actions: [ToastAction(t("Show in Dock", "Mostrar en el Dock")) { Preferences.shared.alwaysShowInDock = true }], duration: 12)
    }

    private func applyAppearance() {
        switch prefs.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(); main.addItem(item)
            let m = NSMenu(title: title); build(m); item.submenu = m
        }
        submenu("Pik") { m in
            m.addItem(withTitle: t("About Pik", "Acerca de Pik"), action: #selector(showAbout), keyEquivalent: "").target = self
            m.addItem(.separator())
            let s = m.addItem(withTitle: t("Settings…", "Ajustes…"), action: #selector(showSettings), keyEquivalent: ","); s.target = self
            m.addItem(.separator())
            m.addItem(withTitle: t("Hide Pik", "Ocultar Pik"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            m.addItem(withTitle: t("Quit Pik", "Salir de Pik"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        submenu(t("Edit", "Edición")) { m in
            m.addItem(withTitle: t("Undo", "Deshacer"), action: Selector(("undo:")), keyEquivalent: "z")
            m.addItem(withTitle: t("Redo", "Rehacer"), action: Selector(("redo:")), keyEquivalent: "Z")
            m.addItem(.separator())
            m.addItem(withTitle: t("Cut", "Cortar"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            m.addItem(withTitle: t("Copy", "Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            m.addItem(withTitle: t("Paste", "Pegar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            m.addItem(withTitle: t("Select All", "Seleccionar todo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
        submenu(t("Window", "Ventana")) { m in
            m.addItem(withTitle: t("Minimize", "Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            m.addItem(withTitle: t("Close", "Cerrar"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            let lib = m.addItem(withTitle: t("Library", "Biblioteca"), action: #selector(showLibrary), keyEquivalent: "l"); lib.target = self
        }
        NSApp.mainMenu = main
    }

    @objc private func showSettings() { AppWindows.showSettings() }
    @objc private func showAbout() { AppWindows.showSettings(tab: .about) }
    @objc private func showLibrary() { AppWindows.showLibrary() }
}
