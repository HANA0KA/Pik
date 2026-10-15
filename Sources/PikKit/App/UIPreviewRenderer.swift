import AppKit
import SwiftUI

/// Renderiza las pantallas de Pik a PNG sin mostrar ventanas ni pedir permisos (`Pik --render-ui <carpeta>`).
/// Usa datos de muestra en un directorio aislado (PIK_DATA_DIR / PIK_DEFAULTS_SUITE).
@MainActor
public enum UIPreviewRenderer {
    public static func run(outputDir: URL) {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let prefs = Preferences.shared
        prefs.language = "en"
        let ids = seed()

        func shot<V: View>(_ name: String, _ size: CGSize, dark: Bool = false, backdrop: Bool = false, @ViewBuilder _ v: () -> V) {
            let root = ZStack {
                if backdrop { LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.5), Color(red: 0.55, green: 0.4, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                v()
            }
            .environment(\.colorScheme, dark ? .dark : .light)
            .environmentObject(prefs)
            render(root, size: size, dark: dark, to: outputDir.appendingPathComponent(name + ".png"))
        }

        // Barra de controles y popovers
        for (name, pop) in [("bar", nil), ("bar-camera", ControlsModel.Popover.camera), ("bar-mic", .mic), ("bar-privacy", .privacy), ("bar-more", .more)] as [(String, ControlsModel.Popover?)] {
            let m = ControlsModel(); m.popover = pop
            shot(name, CGSize(width: 640, height: pop == nil ? 120 : 520), backdrop: true) { ControlsBarView(model: m) }
        }
        let sel = ControlsModel(); sel.selectionText = "1280 × 720"
        shot("bar-selection", CGSize(width: 640, height: 120), backdrop: true) { ControlsBarView(model: sel) }

        // HUD, notas, toast
        shot("hud", CGSize(width: 140, height: 360), backdrop: true) { RecordingHUDView(model: HUDModel()) }
        shot("notes", CGSize(width: 420, height: 500), backdrop: true) { SpeakerNotesView(onClose: {}) }
        let tm = ToastModel(title: "Recording saved", subtitle: "1:02 · Sprint demo", image: nil, symbol: "checkmark.circle.fill",
                            actions: [ToastAction("Open", symbol: "play.fill") {}, ToastAction("Copy link", symbol: "link") {}, ToastAction("Show in Finder", symbol: "folder") {}])
        shot("toast", CGSize(width: 440, height: 130), backdrop: true) { ToastView(model: tm) }

        // Biblioteca
        for tab in LibraryTab.allCases {
            LibraryNavigation.shared.tab = tab
            shot("library-\(tab.rawValue)", CGSize(width: 1020, height: 680)) { LibraryWindowView() }
        }
        LibraryNavigation.shared.tab = .videos
        shot("library-videos-dark", CGSize(width: 1020, height: 680), dark: true) { LibraryWindowView() }

        // Vistas previas
        shot("preview-video", CGSize(width: 1120, height: 720)) { PreviewWindowView(itemID: ids.video) }

        // Ajustes
        for tab in SettingsTab.allCases {
            SettingsNavigation.shared.tab = tab
            shot("settings-\(tab.rawValue)", CGSize(width: 640, height: tab == .about ? 520 : tab == .general ? 1700 : 900)) { SettingsWindowView() }
        }

        // Onboarding y permisos
        shot("setup", CGSize(width: 520, height: 640)) { SetupView() }
        shot("onboarding", CGSize(width: 760, height: 560)) { OnboardingView() }
        print("Listo: \(outputDir.path)")
    }

    /// Piezas reales de la interfaz en español para el video promocional (`Pik --render-promo <carpeta>`).
    /// Barra, HUD, cuenta atrás, notas y aviso salen con fondo transparente; biblioteca y vista previa, a ventana completa.
    public static func runPromo(outputDir: URL) {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let prefs = Preferences.shared
        prefs.language = "es"
        prefs.appearance = .light
        prefs.cameraEnabled = true
        prefs.micEnabled = true
        prefs.defaultPrivacy = .onlyMe
        seedNotes(es: true)
        let ids = seed()
        func out(_ name: String) -> URL { outputDir.appendingPathComponent(name + ".png") }

        // Barra de grabación: cada modo × (cámara, micrófono) y los menús abiertos
        for mode in RecordingMode.allCases {
            for cam in [false, true] {
                for mic in [false, true] {
                    prefs.mode = mode; prefs.cameraEnabled = cam; prefs.micEnabled = mic
                    renderFit(ControlsBarView(model: ControlsModel()), to: out("bar-\(mode.rawValue)-c\(cam ? 1 : 0)m\(mic ? 1 : 0)"))
                }
            }
        }
        prefs.mode = .display; prefs.cameraEnabled = true; prefs.micEnabled = true
        for (name, pop, page) in [("bar-more", ControlsModel.Popover.more, ControlsModel.MorePage.menu),
                                  ("bar-more-settings", .more, .settings), ("bar-more-backgrounds", .more, .backgrounds),
                                  ("bar-privacy", .privacy, .menu)] {
            let m = ControlsModel(); m.popover = pop; m.morePage = page
            renderFit(ControlsBarView(model: m), to: out(name))
        }

        // HUD mientras grabás: segundos 0…20 × punto REC (tenue/brillante) × normal, en pausa o con la paleta de dibujo (6 colores)
        let engine = RecordingEngine.shared
        for sec in 0...20 {
            engine.setPreviewState(phase: .recording, elapsed: Double(sec))
            for blink in [false, true] {
                renderFit(RecordingHUDView(model: HUDModel(), blinkOverride: blink), to: out("hud-rec-\(sec)\(blink ? "b" : "")"))
                for k in 0..<6 {
                    let hm = HUDModel(); hm.drawEnabled = true; hm.drawColorIndex = k
                    renderFit(RecordingHUDView(model: hm, blinkOverride: blink), to: out("hud-draw\(k)-\(sec)\(blink ? "b" : "")"))
                }
            }
            engine.setPreviewState(phase: .paused, elapsed: Double(sec))
            renderFit(RecordingHUDView(model: HUDModel(), blinkOverride: false), to: out("hud-pause-\(sec)"))
        }
        engine.setPreviewState(phase: .idle, elapsed: 0)
        renderFit(FoxLogoView(size: 44, style: .silhouette, tint: .white), to: out("fox-mark"))

        // Cuenta atrás, notas y aviso
        for n in 1...3 {
            let m = CountdownModel(); m.value = n; m.pulse = true
            renderFit(CountdownView(model: m), to: out("countdown-\(n)"))
        }
        renderFit(SpeakerNotesView(onClose: {}), to: out("notes"))
        let tm = ToastModel(title: "Grabación guardada", subtitle: "0:16 · Demo de Pik", image: nil, symbol: "checkmark.circle.fill",
                            actions: [ToastAction("Abrir", symbol: "play.fill") {}, ToastAction("Mostrar en Finder", symbol: "folder") {}])
        renderFit(ToastView(model: tm), to: out("toast"))

        // Biblioteca y vista previa (ventana completa)
        func win<V: View>(_ name: String, _ size: CGSize, @ViewBuilder _ v: () -> V) {
            render(v().environmentObject(prefs), size: size, dark: false, to: out(name))
        }
        LibraryNavigation.shared.tab = .videos
        win("library-videos", CGSize(width: 1020, height: 680)) { LibraryWindowView() }
        // Vista previa con «Detalles» (enlace de ejemplo): privada y con enlace
        PreviewModel.promoLink = "http://mi-mac.local:8420/v/k7Q2x9"
        LibraryStore.shared.setPrivacy(ids.video, .onlyMe)
        win("preview-private", CGSize(width: 1120, height: 640)) { PreviewWindowView(itemID: ids.video) }
        LibraryStore.shared.setPrivacy(ids.video, .anyoneWithLink)
        win("preview-link", CGSize(width: 1120, height: 640)) { PreviewWindowView(itemID: ids.video) }
        PreviewModel.promoLink = nil
        let linkToast = ToastModel(title: "Enlace copiado", subtitle: "Cualquiera en tu red puede abrirlo.", image: nil, symbol: "link", actions: [])
        renderFit(ToastView(model: linkToast), to: out("toast-link"))
        print("Listo: \(outputDir.path)")
    }

    /// Como `render`, pero con el tamaño natural de la vista y fondo transparente.
    private static func renderFit<V: View>(_ view: V, to url: URL) {
        let host = NSHostingView(rootView: view.padding(48))      // margen para que las sombras no se recorten
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    /// Diagnóstico: mide cómo se mueve el panel de la barra al abrir popovers (imprime marcos).
    public static func probeControlsPanel() {
        let model = ControlsModel()
        let host = PanelHost(level: PikLevel.controls, allowsKey: true, excludedFromCapture: true, anchor: .bottomCenter) { ControlsBarView(model: model) }
        let screen = ScreenGeometry.screenUnderMouse()
        var sets: [NSRect] = []
        host.show(centeredOn: screen, bottomInset: 10)
        host.panel.onFrameSet = { sets.append($0) }
        func wait() { RunLoop.current.run(until: Date().addingTimeInterval(0.8)) }
        func report(_ label: String) {
            print(label, host.panel.frame.integral, "level:", host.panel.level.rawValue, "| marcos pedidos:", sets.map { "y\(Int($0.minY))/h\(Int($0.height))" }.joined(separator: " "))
            sets.removeAll()
        }
        wait(); report("barra")
        for p in [ControlsModel.Popover.camera, .mic, .privacy, .more] {
            model.toggle(p); wait(); report("\(p)")
            model.toggle(p); wait(); report("cerrado")
        }
        host.close()
    }

    // MARK: Render

    private static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    // MARK: Datos de muestra

    private static func seed() -> (video: UUID, Void) {
        let store = LibraryStore.shared
        let dir = Storage.appSupport.appendingPathComponent("Sample", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var video = UUID()
        let es = Preferences.shared.language == "es"
        let titles = es ? ["Demo de Pik", "Error en el pago", "Guía de bienvenida", "Resumen semanal", "Revisión de diseño", "Truco: atajos"]
                        : ["Sprint demo", "Checkout bug repro", "Onboarding walkthrough", "Weekly update", "Design review", "Quick tip: shortcuts"]
        for (i, title) in titles.enumerated().reversed() {
            var e = LibraryEntry(kind: .video, title: title, createdAt: Date().addingTimeInterval(-Double(i) * 9_000 - 600),
                                 filePath: dir.appendingPathComponent("v\(i).mp4").path, duration: i == 0 && es ? 16 : 62 + Double(i) * 41, width: 1920, height: 1080,
                                 fileSize: 14_000_000 + Int64(i) * 3_000_000, mode: .display, hasCamera: i % 2 == 0, hasMic: true,
                                 hasSystemAudio: i == 3, privacy: i % 3 == 0 ? .anyoneWithLink : .onlyMe)
            e.recovered = i == 4 && !es
            if i == 1 && !es { e.processing = .transcribing }
            if i == 0 {
                e.transcript = sampleTranscript()
                video = e.id
            }
            store.add(e); thumbnail(for: e, hue: Double(i) / 7, index: i)
        }
        seedNotes(es: es)
        return (video, ())
    }

    /// Notas de muestra (la primera es la que aparece en pantalla).
    private static func seedNotes(es: Bool) {
        let store = NotesStore.shared
        guard store.notes.isEmpty else { return }
        let items: [(String, String)] = es
            ? [("Guion del demo", "Hola, hoy te muestro cómo funciona Pik.\n\n• Elegimos qué grabar con la barra\n• Dibujamos para resaltar lo importante\n• Pausamos con un gesto de la mano\n\nCierre: compartimos el enlace."),
               ("Tutorial: atajos", "1. Abrir controles: ⌃⌥P\n2. Iniciar y detener: ⌃⌥R\n3. Pausar: ⌃⌥T"),
               ("Reunión semanal", "Avances de la semana\nBloqueos\nPróximos pasos")]
            : [("Demo script", "Hi, today I'll show you how Pik works.\n\n• Pick what to record from the bar\n• Say “Pik” and the countdown starts\n• Draw to highlight what matters\n\nClosing: thanks for watching."),
               ("Tutorial: shortcuts", "1. Open controls: ⌃⌥P\n2. Start and stop: ⌃⌥R\n3. Pause: ⌃⌥T"),
               ("Weekly sync", "Progress this week\nBlockers\nNext steps")]
        for item in items.reversed() { store.add(title: item.0, text: item.1) }
        if let first = store.notes.first { store.setActive(first.id) }
    }

    private static func sampleTranscript() -> [TranscriptSegment] {
        let es = Preferences.shared.language == "es"
        let lines = es ? ["Hola, gracias por acompañarme.", "Les muestro cómo grabo mi pantalla con Pik.", "Dibujo para resaltar lo importante.", "Mi cámara aparece en una burbuja.", "Mis notas del orador solo las veo yo.", "Ahora pauso con un gesto.", "Sigo, y termino con otro."]
                    : ["Hi everyone, thanks for joining.", "Let me share my screen and show you what changed this sprint.",
                     "First, link sharing: you can copy a link and anyone on the network can watch.", "Second, exports are much faster now.",
                     "We also added speaker notes with a teleprompter.", "Any questions so far?", "Great, then let's talk about next week."]
        return lines.enumerated().map { TranscriptSegment(id: $0.offset, start: Double($0.offset) * (es ? 3.3 : 6.5), duration: es ? 3.2 : 6, text: $0.element) }
    }

    private static func thumbnail(for e: LibraryEntry, hue: Double, index: Int? = nil) {
        // Miniaturas propias del video promocional: PIK_PROMO_THUMBS=<carpeta con thumb-0.jpg …>
        if let index, let dir = ProcessInfo.processInfo.environment["PIK_PROMO_THUMBS"] {
            let src = URL(fileURLWithPath: dir).appendingPathComponent("thumb-\(index).jpg")
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.removeItem(at: e.thumbnailURL)
                try? FileManager.default.copyItem(at: src, to: e.thumbnailURL)
                return
            }
        }
        let img = sampleImage(size: CGSize(width: 640, height: 400), hue: hue, label: nil)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpg.write(to: e.thumbnailURL)
        }
    }

    private static func sampleImage(size: CGSize, hue: Double, label: String?) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1), NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.75, alpha: 1)])
            g?.draw(in: rect, angle: -40)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.width * 0.12, y: rect.height * 0.18, width: rect.width * 0.76, height: rect.height * 0.64), xRadius: 14, yRadius: 14).fill()
            NSColor.black.withAlphaComponent(0.08).setFill()
            for i in 0..<5 { NSBezierPath(roundedRect: CGRect(x: rect.width * 0.17, y: rect.height * (0.70 - Double(i) * 0.1), width: rect.width * (0.5 - Double(i) * 0.04), height: rect.height * 0.04), xRadius: 5, yRadius: 5).fill() }
            if let label {
                (label as NSString).draw(at: CGPoint(x: rect.width * 0.17, y: rect.height * 0.22), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.black.withAlphaComponent(0.5)])
            }
            return true
        }
    }
}
