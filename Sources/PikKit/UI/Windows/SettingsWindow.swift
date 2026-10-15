import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Piezas

private struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            if let footer { Text(footer).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 4) }
        }
    }
}

private struct PickerRow<V: Hashable>: View {
    let title: String
    @Binding var selection: V
    let options: [(V, String)]
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Picker("", selection: $selection) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }
                .labelsHidden().fixedSize()
        }
    }
}

private func toggle(_ title: String, _ binding: Binding<Bool>, help: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Toggle(isOn: binding) { Text(title).font(.system(size: 13)) }.toggleStyle(.switch)
        if let help { Text(help).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 40) }
    }
}

// MARK: - Ventana

struct SettingsWindowView: View {
    @ObservedObject private var nav = SettingsNavigation.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { nav.tab = tab } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol).font(.system(size: 18))
                            Text(tab.title).font(.system(size: 11.5, weight: .medium))
                        }
                        .frame(width: 84, height: 52)
                        .background(RoundedRectangle(cornerRadius: 10).fill(nav.tab == tab ? Theme.accent.opacity(0.16) : .clear))
                        .foregroundStyle(nav.tab == tab ? Theme.accentDeep : Color.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 34).padding(.bottom, 10)
            Divider()
            ScrollView {
                Group {
                    switch nav.tab {
                    case .general: GeneralSettings()
                    case .shortcuts: ShortcutSettings()
                    case .gestures: GestureSettings()
                    case .account: AccountSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Appearance", "Apariencia")) {
                PickerRow(title: t("Theme", "Tema"), selection: $prefs.appearance, options: AppearanceMode.allCases.map { ($0, $0.title) })
                PickerRow(title: t("Language", "Idioma"), selection: $prefs.language,
                          options: [("system", t("System (\(L10n.name(of: L10n.systemLanguage())))", "Sistema (\(L10n.name(of: L10n.systemLanguage())))")), ("en", "English"), ("es", "Español")])
            }
            SettingsCard(title: t("Startup", "Inicio")) {
                toggle(t("Open Pik at login", "Abrir Pik al iniciar sesión"), Binding(get: { launchAtLogin }, set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                toggle(t("Show Pik in the Dock", "Mostrar Pik en el Dock"), $prefs.alwaysShowInDock)
                toggle(t("Open recording controls when Pik is opened", "Abrir los controles al abrir Pik"), $prefs.openControlsOnActivate)
            }
            SettingsCard(title: t("Recording", "Grabación")) {
                PickerRow(title: t("Quality", "Calidad"), selection: $prefs.resolution, options: VideoResolution.allCases.map { ($0, $0.title) })
                PickerRow(title: t("Frame rate", "Fotogramas por segundo"), selection: $prefs.fps, options: [(24, "24 fps"), (30, "30 fps"), (60, "60 fps")])
                toggle(t("HEVC (smaller files)", "HEVC (archivos más chicos)"), $prefs.useHEVC, help: t("Not every player can open HEVC.", "No todos los reproductores abren HEVC."))
                toggle(t("Record system audio", "Grabar audio del sistema"), $prefs.includeSystemAudio)
                toggle(t("Reduce microphone noise", "Reducir ruido del micrófono"), $prefs.noiseSuppression)
                toggle(t("Hide menu bar and Dock", "Ocultar barra de menús y Dock"), $prefs.hideSystemUI)
                toggle(t("Hide desktop icons", "Ocultar íconos del escritorio"), $prefs.hideDesktopIcons)
                toggle(t("Countdown before recording", "Cuenta regresiva antes de grabar"), $prefs.showCountdown)
                toggle(t("Highlight mouse clicks", "Resaltar clics del mouse"), $prefs.highlightClicks)
                toggle(t("Transcribe recordings automatically", "Transcribir grabaciones automáticamente"), $prefs.autoTranscribe)
                PickerRow(title: t("Transcription language", "Idioma de la transcripción"), selection: $prefs.transcriptionLanguage,
                          options: [("auto", t("Automatic (Spanish / English)", "Automático (español / inglés)")), ("es", "Español"), ("en", "English")])
                Text(t("Automatic detects whether you speak Spanish or English. It applies to new recordings.",
                       "Automático detecta si hablás en español o en inglés. Se aplica a las grabaciones nuevas."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            SettingsCard(title: t("When finished", "Al terminar")) {
                PickerRow(title: t("After recording", "Después de grabar"), selection: $prefs.afterRecording, options: AfterRecordingAction.allCases.map { ($0, $0.title) })
                toggle(t("Recording sounds", "Sonidos de grabación"), $prefs.videoSounds)
            }
            if #available(macOS 26.0, *) {
                SettingsCard(title: t("Voice activation", "Activación por voz")) {
                    toggle(t("Say “Pik” to start recording", "Decí «Pik» para empezar a grabar"), $prefs.voiceActivation,
                           help: t("Pik listens through the microphone on your Mac while it is idle and never saves or sends what it hears. It stops listening when you record. The countdown lets you cancel by mistake.",
                                   "Pik escucha por el micrófono, en tu Mac, mientras está en reposo y nunca guarda ni envía lo que oye. Deja de escuchar al grabar. La cuenta regresiva te deja cancelar si se activó sin querer."))
                }
            }
        }
    }
}

// MARK: - Gestos

private struct GestureSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var store = GestureStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Hand gestures", "Gestos de mano"),
                         footer: t("While this is on, Pik uses the camera (the green light turns on) to look for your hand. The video is analyzed on your Mac, never saved or sent.",
                                   "Mientras esté activado, Pik usa la cámara (se enciende la luz verde) para buscar tu mano. El video se analiza en tu Mac, no se guarda ni se envía.")) {
                toggle(t("Control recording with hand gestures", "Controlar la grabación con gestos de mano"), $prefs.gestureControl,
                       help: t("Record your own gesture for each action, hold it for a second and Pik acts.", "Grabá tu propio gesto para cada acción, mantenelo un segundo y Pik actúa."))
                PickerRow(title: t("Sensitivity", "Sensibilidad"), selection: $prefs.gestureSensitivity,
                          options: [(0.8, t("Strict", "Estricta")), (1.0, t("Normal", "Normal")), (1.25, t("Flexible", "Flexible"))])
            }
            SettingsCard(title: t("Your gestures", "Tus gestos"),
                         footer: t("Use one hand, fully visible, and pick poses that look clearly different from each other.", "Usá una sola mano, bien visible, y elegí poses que se vean claramente distintas entre sí.")) {
                ForEach(GestureAction.allCases) { a in
                    HStack(spacing: 10) {
                        Image(systemName: a.symbol).font(.system(size: 18)).frame(width: 26).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(.system(size: 13, weight: .medium))
                            Text(store.template(for: a) != nil ? t("Saved", "Guardado") : t("No gesture yet", "Sin gesto todavía"))
                                .font(.system(size: 11.5)).foregroundStyle(store.template(for: a) != nil ? Color.green : Color.secondary)
                        }
                        Spacer()
                        if store.template(for: a) != nil {
                            Button(t("Delete", "Borrar")) { store.remove(a) }
                        }
                        Button(store.template(for: a) == nil ? t("Record gesture", "Grabar gesto") : t("Change", "Cambiar")) {
                            AppWindows.showGestureRecorder(action: a)
                        }
                    }
                    if a != GestureAction.allCases.last { Divider() }
                }
            }
        }
    }
}

// MARK: - Atajos

private struct ShortcutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Global shortcuts work from any app. Click a shortcut to change it.", "Los atajos globales funcionan desde cualquier app. Tocá un atajo para cambiarlo."))
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
            SettingsCard(title: t("Shortcuts", "Atajos")) {
                ForEach(ShortcutAction.allCases) { a in
                    ShortcutRow(action: a)
                    if a != ShortcutAction.allCases.last { Divider() }
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @State private var current: Shortcut?
    @State private var recording = false
    @State private var message: String?
    @State private var suggestion: Shortcut?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title).font(.system(size: 13))
                Spacer()
                Button { recording ? stop() : start() } label: {
                    Text(recording ? t("Press keys…", "Apretá las teclas…") : (current?.display ?? t("Not set", "Sin asignar")))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded)).frame(minWidth: 96)
                }
                .buttonStyle(PikSecondaryButtonStyle())
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(recording ? Theme.accent : .clear, lineWidth: 2))
                Button { ShortcutManager.shared.reset(action); refresh(); message = nil } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(PikSecondaryButtonStyle()).help(t("Reset", "Restablecer"))
                Button { ShortcutManager.shared.setShortcut(nil, for: action); refresh(); message = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(PikSecondaryButtonStyle()).help(t("Remove", "Quitar"))
            }
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    if let suggestion {
                        Button(t("Use \(suggestion.display)", "Usar \(suggestion.display)")) {
                            ShortcutManager.shared.setShortcut(suggestion, for: action); refresh(); self.message = nil; self.suggestion = nil
                        }.buttonStyle(PikSecondaryButtonStyle())
                    }
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutManager.didChange)) { _ in refresh() }
        .onDisappear { stop() }
    }

    private func refresh() { current = ShortcutManager.shared.shortcut(for: action) }

    private func start() {
        recording = true; message = nil; suggestion = nil
        ShortcutManager.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        ShortcutManager.shared.registerAll()
    }

    private func handle(_ e: NSEvent) {
        let mods = Shortcut.carbonModifiers(from: e.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if e.keyCode == UInt16(kVK_Escape) { stop(); return }
        if mods == 0, e.keyCode == UInt16(kVK_Delete) || e.keyCode == UInt16(kVK_ForwardDelete) {
            stop(); ShortcutManager.shared.setShortcut(nil, for: action); refresh(); return
        }
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            message = t("Include ⌃, ⌥ or ⌘ so it doesn't clash with typing.", "Incluí ⌃, ⌥ o ⌘ para que no choque con escribir."); return
        }
        let candidate = Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods)
        let mgr = ShortcutManager.shared
        if let other = mgr.action(using: candidate, excluding: action) {
            message = t("\(candidate.display) is already used by “\(other.title)”.", "\(candidate.display) ya lo usa «\(other.title)».")
            suggestion = mgr.suggestedShortcut(for: action); stop(); return
        }
        if candidate.conflictsWithSystem() {
            message = t("\(candidate.display) is a macOS shortcut.", "\(candidate.display) es un atajo de macOS.")
            suggestion = mgr.suggestedShortcut(for: action); stop(); return
        }
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        mgr.setShortcut(candidate, for: action)
        refresh()
    }
}

// MARK: - Cuenta

private struct AccountSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var store = LibraryStore.shared
    @State private var portText = ""
    @State private var serverRunning = ShareServer.shared.isRunning

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Profile", "Perfil")) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                        Text(String(prefs.userName.first ?? "P").uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }.frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(t("Your name", "Tu nombre"), text: $prefs.userName).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        Text(t("Pik keeps everything on this Mac. No account needed.", "Pik guarda todo en este Mac. No hace falta cuenta.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                PickerRow(title: t("Default privacy", "Privacidad por defecto"), selection: $prefs.defaultPrivacy, options: PrivacyLevel.allCases.map { ($0, $0.title) })
            }
            SettingsCard(title: t("Storage", "Almacenamiento"), footer: t("Videos are saved as MP4 files you can move or back up.", "Los videos se guardan como archivos MP4 que podés mover o respaldar.")) {
                let folder = Storage.videosFolder(prefs)
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text((folder.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                HStack {
                    Button(t("Choose…", "Elegir…")) { chooseFolder() }.buttonStyle(PikSecondaryButtonStyle())
                    Button(t("Show in Finder", "Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(PikSecondaryButtonStyle())
                    if prefs.libraryFolderPath != nil { Button(t("Use default", "Usar la carpeta por defecto")) { prefs.libraryFolderPath = nil }.buttonStyle(PikSecondaryButtonStyle()) }
                    Spacer()
                    let bytes = store.items.reduce(Int64(0)) { $0 + $1.fileSize }
                    Text(t("\(store.items.count) items · \(Fmt.bytes(bytes))", "\(store.items.count) elementos · \(Fmt.bytes(bytes))")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            SettingsCard(title: t("Link sharing", "Compartir por enlace"),
                         footer: t("“Copy link” gives a link served by Pik from this Mac. It works on your network while Pik is running.",
                                   "«Copiar enlace» da un enlace servido por Pik desde este Mac. Funciona en tu red mientras Pik esté abierto.")) {
                toggle(t("Enable link sharing", "Activar compartir por enlace"), $prefs.sharingEnabled)
                HStack {
                    Text(t("Port", "Puerto")).font(.system(size: 13))
                    TextField("8420", text: $portText).textFieldStyle(.roundedBorder).frame(width: 80)
                        .onSubmit { if let p = Int(portText), (1024...65535).contains(p) { prefs.sharePort = p } else { portText = String(prefs.sharePort) } }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(serverRunning ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(serverRunning ? t("Running on port \(ShareServer.shared.port)", "Activo en el puerto \(ShareServer.shared.port)") : t("Off", "Apagado"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if serverRunning, let ip = ShareServer.lanIPv4() {
                    Text("http://\(ShareServer.hostName):\(ShareServer.shared.port)  ·  http://\(ip):\(ShareServer.shared.port)")
                        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            SettingsCard(title: t("Permissions", "Permisos")) { PermissionsList() }
        }
        .onAppear { portText = String(prefs.sharePort); serverRunning = ShareServer.shared.isRunning }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in serverRunning = ShareServer.shared.isRunning }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = t("Choose", "Elegir")
        if p.runModal() == .OK, let url = p.url { prefs.libraryFolderPath = url.path }
    }
}

// MARK: - Acerca de

private struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 18) {
            PikAppIconView(size: 110)
            VStack(spacing: 4) {
                Text("Pik").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(t("Version \(version)", "Versión \(version)")).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Text(t("Record your screen, camera and voice. Share with a link. Everything stays on your Mac.",
                   "Grabá tu pantalla, cámara y voz. Compartí con un enlace. Todo queda en tu Mac."))
                .font(.system(size: 13)).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }
}
