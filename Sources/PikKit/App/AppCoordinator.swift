import AppKit
import Combine
import Foundation

/// Orquesta el flujo completo: barra de controles → selección → cuenta regresiva → grabación → HUD → guardado.
@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public private(set) var phase: RecordingPhase = .idle
    @Published public private(set) var elapsed: TimeInterval = 0

    private let prefs = Preferences.shared
    private let engine = RecordingEngine.shared
    private let controlsModel = ControlsModel()
    private var controlsHost: PanelHost?
    private let areaSelector = AreaSelectionController()
    private let windowPicker = WindowPickerController()
    private let displayPicker = DisplayPickerController()
    private let countdown = CountdownController()
    private let hud = RecordingHUDController()
    private let bubble = CameraBubbleController()
    private let notes = SpeakerNotesController()
    private let clicks = ClickHighlightController()
    private let drawing = DrawOverlayController()
    private let background = RecordingBackgroundController()
    private var bag = Set<AnyCancellable>()

    private var pickedWindow: PickedWindow?
    private var selectedArea: CGRect?              // coordenadas globales de AppKit
    private var selectedDisplay: CGDirectDisplayID?
    private var displayChosen = false
    private var lastRequest: RecordingRequest?
    private var selectionGeneration = 0
    private var diskTimer: Timer?

    private init() {
        wireControls()
        wireHUD()
        notes.onVisibilityChange = { [weak self] visible in self?.hud.model.notesVisible = visible }
        bubble.onClosedByUser = { [weak self] in
            guard let self else { return }
            self.prefs.cameraEnabled = false
            if self.phase == .armed { CameraController.shared.stop() }
        }
        controlsModel.$popover.receive(on: DispatchQueue.main).sink { if $0 != nil { CoachMarkController.shared.dismiss() } }.store(in: &bag)
        engine.$elapsed.receive(on: DispatchQueue.main).sink { [weak self] in self?.elapsed = $0 }.store(in: &bag)
        engine.onUnexpectedStop = { [weak self] err in Task { @MainActor in self?.handleUnexpectedStop(err) } }
    }

    // MARK: API pública

    public var isRecording: Bool { phase == .recording || phase == .paused }
    public var isBusy: Bool { phase != .idle }

    public func toggleControls() {
        if phase == .armed { closeControls() } else { openControls() }
    }

    /// Abre la barra de controles (o la trae al frente). `mode` fuerza un modo.
    public func openControls(mode: RecordingMode? = nil) {
        if phase == .armed {
            controlsHost?.panel.orderFrontRegardless()
            if let mode, mode != prefs.mode { prefs.mode = mode; applyMode(mode, initial: false) }
            return
        }
        guard phase == .idle else { return }
        Permissions.shared.refresh()
        let wanted = mode ?? prefs.mode
        if wanted != .cameraOnly, !Permissions.shared.isGranted(.screen) {
            AppWindows.showSetup()
            return
        }
        if let mode { prefs.mode = mode }
        phase = .armed
        pickedWindow = nil; selectedArea = nil; displayChosen = false
        let screen = ScreenGeometry.screenUnderMouse()
        selectedDisplay = screen.pikDisplayID

        let host = PanelHost(level: PikLevel.controls, allowsKey: true, excludedFromCapture: true, anchor: .bottomCenter) {
            ControlsBarView(model: self.controlsModel)
        }
        host.panel.onEscape = { [weak self] in self?.closeControls() }
        controlsHost = host
        host.show(centeredOn: screen, bottomInset: 10)
        CoachMarkController.shared.showIfNeeded(above: host.panel)

        if prefs.cameraEnabled || prefs.mode == .cameraOnly { showBubble(on: screen) }
        if prefs.showNotes { notes.show(on: screen) }
        if prefs.mode != .display { applyMode(prefs.mode, initial: true) }
        WindowManager.shared.updateDockPolicy()
    }

    public func closeControls() {
        guard phase == .armed || phase == .countdown else { return }
        selectionGeneration += 1
        areaSelector.cancel(); windowPicker.cancel(); countdown.cancel()
        controlsHost?.close(); controlsHost = nil
        CoachMarkController.shared.dismiss()
        controlsModel.popover = nil
        controlsModel.selectionText = nil
        controlsModel.isStarting = false
        bubble.hide()
        if !engine.isActive { CameraController.shared.stop() }
        notes.destroy()
        background.hide()
        phase = .idle
    }

    public func startOrStop() {
        switch phase {
        case .idle: openControls()
        case .armed: recordPressed()
        case .recording, .paused: stopRecording()
        default: break
        }
    }

    /// Activación por voz: abre la barra y arranca (con la cuenta regresiva si está activa, para poder cancelar).
    public func startFromVoice() {
        if phase == .idle { openControls() }
        if phase == .armed { recordPressed() }
    }

    /// Gestos de mano: iniciar (en reposo o con la barra abierta), pausar/reanudar y detener (grabando).
    public func performGesture(_ action: GestureAction) {
        switch action {
        case .start: if phase == .idle || phase == .armed { startFromVoice() }
        case .pause: if isRecording { togglePause() }
        case .stop: if isRecording { stopRecording() }
        }
    }

    public func togglePause() {
        guard isRecording else { return }
        engine.togglePause()
        phase = engine.phase == .paused ? .paused : .recording
        SoundPlayer.shared.play(phase == .paused ? .pause : .resume, enabled: prefs.videoSounds)
    }

    public func stopRecording() {
        guard isRecording else { return }
        phase = .finishing
        Task { await finishRecording(error: nil) }
    }

    /// Cancela: con la barra abierta la cierra; grabando pide confirmación y descarta.
    public func cancelCurrent(confirm: Bool = true) {
        switch phase {
        case .armed, .countdown: closeControls()
        case .recording, .paused:
            if confirm {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = t("Delete this recording?", "¿Eliminar esta grabación?")
                alert.informativeText = t("You can't undo this.", "No se puede deshacer.")
                alert.addButton(withTitle: t("Delete", "Eliminar"))
                alert.addButton(withTitle: t("Keep recording", "Seguir grabando"))
                alert.buttons.first?.hasDestructiveAction = true
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            guard isRecording else { return }
            phase = .finishing
            Task {
                diskTimer?.invalidate()
                await engine.cancel()
                teardownRecordingUI()
                phase = .idle
                ToastPresenter.shared.show(title: t("Recording deleted", "Grabación eliminada"), symbol: "trash", duration: 3)
            }
        default: break
        }
    }

    // MARK: Cableado

    private func wireControls() {
        controlsModel.onClose = { [weak self] in self?.closeControls() }
        controlsModel.onRecord = { [weak self] in self?.recordPressed() }
        controlsModel.onModeChange = { [weak self] m in self?.applyMode(m, initial: false) }
        controlsModel.onToggleNotes = { [weak self] in self?.toggleNotes() }
        controlsModel.onOpenSettings = { AppWindows.showSettings() }
        controlsModel.onCameraToggled = { [weak self] on in self?.cameraToggled(on) }
    }

    private func wireHUD() {
        let m = hud.model
        m.onStop = { [weak self] in self?.stopRecording() }
        m.onTogglePause = { [weak self] in self?.togglePause() }
        m.onRestart = { [weak self] in self?.restartRecording() }
        m.onDelete = { [weak self] in self?.cancelCurrent(confirm: true) }
        m.onToggleDraw = { [weak self] on in self?.drawing.setEnabled(on) }
        m.onColor = { [weak self] c in self?.drawing.color = c }
        m.onClearDrawing = { [weak self] in self?.drawing.clear() }
        m.onTogglePersistence = { [weak self] on in self?.drawing.persistent = on }
        m.onToggleNotes = { [weak self] in self?.toggleNotes() }
    }

    private func toggleNotes() {
        notes.toggle(on: currentScreen())
    }

    private func cameraToggled(_ on: Bool) {
        guard phase == .armed else { return }
        if on {
            Permissions.shared.ensure(.camera) { [weak self] ok in
                guard let self else { return }
                if ok { self.showBubble(on: self.currentScreen()) }
                else {
                    self.prefs.cameraEnabled = false
                    self.offerPermissionSettings(.camera)
                }
            }
        } else if prefs.mode != .cameraOnly {
            bubble.hide()
            CameraController.shared.stop()
        }
    }

    private func showBubble(on screen: NSScreen) {
        guard Permissions.shared.isGranted(.camera) else {
            Permissions.shared.ensure(.camera) { [weak self] ok in
                guard let self, self.phase != .idle else { return }
                if ok { self.bubble.show(on: screen, near: self.selectedArea) }
                else { self.prefs.cameraEnabled = false; self.offerPermissionSettings(.camera) }
            }
            return
        }
        bubble.show(on: screen, near: selectedArea)
    }

    private func offerPermissionSettings(_ k: PermissionKind) {
        ToastPresenter.shared.show(title: t("\(k.title) access is off", "El acceso a \(k.title.lowercased()) está desactivado"),
                                   subtitle: t("Allow Pik in System Settings.", "Permití a Pik en Ajustes del Sistema."), symbol: k.symbol,
                                   actions: [ToastAction(t("Open Settings", "Abrir Ajustes")) { Permissions.shared.openSettings(k) }])
    }

    // MARK: Selección de modo

    private func currentScreen() -> NSScreen {
        if prefs.mode == .window, let w = pickedWindow, let s = ScreenGeometry.screen(for: w.displayID) { return s }
        if prefs.mode == .custom, let a = selectedArea,
           let s = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: a.midX, y: a.midY)) }) { return s }
        if let id = selectedDisplay, let s = ScreenGeometry.screen(for: id) { return s }
        if let panel = controlsHost?.panel { return ScreenGeometry.screenContaining(window: panel) }
        return ScreenGeometry.screenUnderMouse()
    }

    private func applyMode(_ mode: RecordingMode, initial: Bool) {
        guard phase == .armed else { return }
        selectionGeneration += 1
        let gen = selectionGeneration
        areaSelector.cancel(); windowPicker.cancel()
        pickedWindow = nil; selectedArea = nil
        controlsModel.selectionText = nil
        controlsModel.popover = nil
        if mode == .cameraOnly || prefs.cameraEnabled { showBubble(on: currentScreen()) }
        else if !prefs.cameraEnabled { bubble.hide() }

        switch mode {
        case .display:
            displayChosen = false
            if !initial, NSScreen.screens.count > 1 {
                Task {
                    let id = await displayPicker.pick()
                    guard gen == selectionGeneration, let id, let s = ScreenGeometry.screen(for: id) else { return }
                    selectedDisplay = id; displayChosen = true
                    controlsHost?.show(centeredOn: s, bottomInset: 10)
                    controlsModel.selectionText = s.localizedName
                }
            }
        case .window:
            Task {
                let w = await windowPicker.pick()
                guard gen == selectionGeneration else { return }
                if let w {
                    pickedWindow = w; selectedDisplay = w.displayID
                    controlsModel.selectionText = w.appName + (w.title.isEmpty ? "" : " – \(w.title)")
                    controlsHost?.panel.orderFrontRegardless()
                } else {
                    fallBackToDisplay()
                }
            }
        case .custom:
            areaSelector.onChange = { [weak self] r in
                guard let self, gen == self.selectionGeneration else { return }
                self.selectedArea = r
                self.controlsModel.selectionText = "\(Int(r.width)) × \(Int(r.height))"
            }
            Task {
                let r = await areaSelector.select(kind: .recording, initial: nil)
                guard gen == selectionGeneration else { return }
                if let r {            // Enter dentro de la selección: grabar ya
                    selectedArea = r
                    recordPressed()
                } else {
                    fallBackToDisplay()
                }
            }
        case .cameraOnly:
            break
        }
    }

    private func fallBackToDisplay() {
        guard phase == .armed else { return }
        prefs.mode = .display
        applyMode(.display, initial: true)
    }

    // MARK: Grabar

    private func recordPressed() {
        guard phase == .armed, !controlsModel.isStarting else { return }
        let mode = prefs.mode
        switch mode {
        case .window where pickedWindow == nil:
            applyMode(.window, initial: false); return
        case .custom where selectedArea == nil:
            ToastPresenter.shared.show(title: t("Drag to choose an area", "Arrastrá para elegir un área"), symbol: "rectangle.dashed", duration: 3)
            return
        default: break
        }
        controlsModel.isStarting = true
        Task {
            await beginRecording(mode: mode)
            controlsModel.isStarting = false
        }
    }

    private func ask(_ k: PermissionKind) async -> Bool {
        await withCheckedContinuation { cont in Permissions.shared.ensure(k) { cont.resume(returning: $0) } }
    }

    private func confirm(_ title: String, _ detail: String, ok: String, cancel: String = t("Cancel", "Cancelar")) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func beginRecording(mode: RecordingMode) async {
        guard phase == .armed else { return }
        var micOn = prefs.micEnabled
        if micOn, !Permissions.shared.isGranted(.microphone) {
            if await !ask(.microphone) {
                if !confirm(t("Microphone is off", "El micrófono está apagado"),
                            t("Pik can't hear you. Record without a microphone?", "Pik no puede escucharte. ¿Grabar sin micrófono?"),
                            ok: t("Record without mic", "Grabar sin micrófono")) {
                    Permissions.shared.openSettings(.microphone); return
                }
                micOn = false
            }
        }
        var camOn = prefs.cameraEnabled || mode == .cameraOnly
        if camOn, !Permissions.shared.isGranted(.camera) {
            if await !ask(.camera) {
                if mode == .cameraOnly { offerPermissionSettings(.camera); return }
                camOn = false; bubble.hide()
            }
        }
        if mode != .cameraOnly, !Permissions.shared.isGranted(.screen) { closeControls(); AppWindows.showSetup(); return }
        if Storage.isLowOnSpace(prefs) {
            let free = Fmt.bytes(Storage.freeBytes(at: Storage.videosFolder(prefs)))
            if !confirm(t("Low disk space", "Poco espacio en disco"),
                        t("Only \(free) free. Long recordings may fail.", "Solo quedan \(free). Las grabaciones largas pueden fallar."),
                        ok: t("Record anyway", "Grabar igual")) { return }
        }

        // Pantalla de referencia y petición
        if mode == .display, !displayChosen, let panel = controlsHost?.panel {
            selectedDisplay = ScreenGeometry.displayID(of: ScreenGeometry.screenContaining(window: panel))
        }
        let screen = currentScreen()
        var req = RecordingRequest(mode: mode, displayID: screen.pikDisplayID)
        req.micOn = micOn
        req.cameraOn = camOn
        if let w = pickedWindow, mode == .window { req.windowID = w.windowID; req.displayID = w.displayID }
        if let a = selectedArea, mode == .custom { req.area = ScreenGeometry.quartz(fromAppKit: a) }

        // Cierra selección + barra
        selectionGeneration += 1
        areaSelector.cancel(); windowPicker.cancel()
        controlsHost?.close(); controlsHost = nil
        CoachMarkController.shared.dismiss()
        controlsModel.popover = nil; controlsModel.selectionText = nil
        phase = .countdown

        if let id = prefs.recordingBackgroundID, mode != .cameraOnly {
            background.show(id: id, onlyOn: mode == .display ? req.displayID : nil)
        }
        if prefs.showCountdown {
            let ok = await countdown.run(on: screen, seconds: 3, sounds: prefs.videoSounds)
            if !ok { restoreArmed(); return }
        }
        guard phase == .countdown else { return }

        hud.show(on: screen)
        hud.model.warning = nil
        hud.model.drawEnabled = false
        hud.model.notesVisible = notes.isVisible
        if prefs.highlightClicks, mode != .cameraOnly { clicks.start() }
        if mode != .cameraOnly { drawing.show() }
        try? await Task.sleep(nanoseconds: 200_000_000)      // que el servidor de ventanas registre los overlays

        req.excludedWindowNumbers = [hud.windowNumber, notes.windowNumber, bubble.controlsWindowNumber].compactMap { $0 }
        req.overlayWindowNumbers = ([bubble.windowNumber] + clicks.windowNumbers.map(Optional.some)
                                    + drawing.windowNumbers.map(Optional.some) + background.windowNumbers.map(Optional.some)).compactMap { $0 }
        lastRequest = req
        do {
            try await engine.start(req)
        } catch {
            plogError("No se pudo iniciar la grabación: \(error.localizedDescription)")
            teardownRecordingUI()
            phase = .idle
            ToastPresenter.shared.show(title: t("Couldn't start recording", "No se pudo iniciar la grabación"), subtitle: error.localizedDescription,
                                       symbol: "exclamationmark.triangle.fill", duration: 8)
            return
        }
        SoundPlayer.shared.play(.start, enabled: prefs.videoSounds)
        phase = .recording
        startDiskWatch()
    }

    /// Cancelaron la cuenta regresiva: vuelve a la barra.
    private func restoreArmed() {
        background.hide()
        phase = .idle
        openControls()
    }

    // MARK: Reinicio / fin

    private func restartRecording() {
        guard isRecording, let req = lastRequest else { return }
        phase = .countdown
        diskTimer?.invalidate()
        Task {
            await engine.cancel()
            if prefs.showCountdown {
                let ok = await countdown.run(on: currentScreen(), seconds: 3, sounds: prefs.videoSounds)
                if !ok { teardownRecordingUI(); phase = .idle; return }
            }
            do {
                try await engine.start(req)
                SoundPlayer.shared.play(.start, enabled: prefs.videoSounds)
                phase = .recording
                startDiskWatch()
            } catch {
                teardownRecordingUI(); phase = .idle
                ToastPresenter.shared.show(title: t("Couldn't restart", "No se pudo reiniciar"), subtitle: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func handleUnexpectedStop(_ err: Error?) {
        guard isRecording else { return }
        phase = .finishing
        Task { await finishRecording(error: err ?? NSError(domain: "Pik", code: 1, userInfo: [NSLocalizedDescriptionKey: t("Capture was interrupted.", "Se interrumpió la captura.")])) }
    }

    private func finishRecording(error: Error?) async {
        diskTimer?.invalidate()
        hud.hide()
        let entry = await engine.stop()
        teardownRecordingUI()
        phase = .idle
        guard let entry else {
            ToastPresenter.shared.show(title: t("The recording couldn't be saved", "No se pudo guardar la grabación"),
                                       subtitle: engine.lastError, symbol: "exclamationmark.triangle.fill", duration: 8)
            return
        }
        if let error {
            ToastPresenter.shared.show(title: t("Recording stopped", "La grabación se detuvo"),
                                       subtitle: error.localizedDescription + " " + t("What was captured was saved.", "Lo capturado se guardó."),
                                       symbol: "exclamationmark.triangle.fill", duration: 8)
        }
        afterRecording(entry, silent: error != nil)
    }

    private func teardownRecordingUI() {
        hud.hide()
        clicks.stop()
        drawing.hide()
        background.hide()
        bubble.hide()
        notes.destroy()
        if !engine.isActive { CameraController.shared.stop() }
        hud.model.drawEnabled = false
        WindowManager.shared.updateDockPolicy()
    }

    private func afterRecording(_ entry: LibraryEntry, silent: Bool) {
        SoundPlayer.shared.play(.complete, enabled: prefs.videoSounds)
        if prefs.autoTranscribe { ItemActions.process(entry.id) }
        LibraryStore.shared.makeThumbnail(for: entry) { [weak self] in
            guard let self else { return }
            let current = LibraryStore.shared.item(id: entry.id) ?? entry
            if !silent { self.presentFinishedToast(current) }
        }
        switch prefs.afterRecording {
        case .openPreview: AppWindows.showPreview(entry.id)
        case .copyLink: ItemActions.copyLink(entry, silent: true)
        case .copyFile: ItemActions.copyFile(entry, silent: true)
        case .revealInFinder: ItemActions.reveal(entry)
        case .nothing: break
        }
    }

    private func presentFinishedToast(_ e: LibraryEntry) {
        var actions = [ToastAction(t("Open", "Abrir"), symbol: "play.fill") { AppWindows.showPreview(e.id) }]
        if prefs.sharingEnabled { actions.append(ToastAction(t("Copy link", "Copiar enlace"), symbol: "link") { ItemActions.copyLink(e) }) }
        actions.append(ToastAction(t("Show in Finder", "Mostrar en Finder"), symbol: "folder") { ItemActions.reveal(e) })
        let linkNote = prefs.afterRecording == .copyLink ? " · " + t("link copied", "enlace copiado") : ""
        ToastPresenter.shared.show(title: t("Recording saved", "Grabación guardada"),
                                   subtitle: "\(Fmt.duration(e.duration)) · \(e.title)\(linkNote)",
                                   image: LibraryStore.shared.thumbnail(for: e), symbol: "checkmark.circle.fill", actions: actions, duration: 9)
    }

    // MARK: Disco

    private func startDiskWatch() {
        diskTimer?.invalidate()
        diskTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                let free = Storage.freeBytes(at: Storage.videosFolder(self.prefs))
                if free < 50_000_000 {
                    ToastPresenter.shared.show(title: t("Disk is full", "El disco está lleno"),
                                               subtitle: t("Recording stopped and saved.", "La grabación se detuvo y se guardó."), symbol: "externaldrive.badge.exclamationmark", duration: 8)
                    self.stopRecording()
                } else if free < 300_000_000 {
                    self.hud.model.warning = t("Low disk space", "Poco espacio en disco")
                }
            }
        }
        RunLoop.main.add(diskTimer!, forMode: .common)
    }
}
