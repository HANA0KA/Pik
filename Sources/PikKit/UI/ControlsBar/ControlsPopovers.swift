import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Piezas comunes

struct PopoverRow: View {
    let symbol: String?
    let title: String
    var subtitle: String? = nil
    var checked = false
    var chevron = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).frame(width: 20).foregroundStyle(.white.opacity(0.8))
                } else {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 20).opacity(checked ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(2) }
                }
                Spacer(minLength: 4)
                if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.4)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(configuration.isPressed ? 0.14 : (hover ? 0.08 : 0))))
            .onHover { hover = $0 }
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var help: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) { Text(title).font(.system(size: 13)) }
                .toggleStyle(.checkbox)
            if let help {
                Image(systemName: "questionmark.circle").foregroundStyle(.white.opacity(0.45)).help(help)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(.white)
    }
}

func pickImageFile() -> URL? {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.image]
    p.allowsMultipleSelection = false
    p.message = t("Choose an image to use as a background", "Elegí una imagen para usar de fondo")
    return p.runModal() == .OK ? p.url : nil
}

// MARK: - Cámara y micrófono

struct DeviceListPopover: View {
    enum Kind { case camera, mic }
    let kind: Kind
    @ObservedObject var model: ControlsModel
    @ObservedObject private var devices = DeviceMonitor.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var audio = AudioInputController.shared
    @ObservedObject private var perms = Permissions.shared
    @ObservedObject private var camera = CameraController.shared

    private var list: [DeviceInfo] { kind == .camera ? devices.cameras : devices.microphones }
    private var permission: PermissionKind { kind == .camera ? .camera : .microphone }
    private var enabled: Bool { kind == .camera ? prefs.cameraEnabled : prefs.micEnabled }
    private var selectedID: String? {
        let stored = kind == .camera ? prefs.cameraDeviceID : prefs.micDeviceID
        if let stored, list.contains(where: { $0.id == stored }) { return stored }
        return kind == .camera ? DeviceCatalog.camera(id: nil)?.uniqueID : DeviceCatalog.microphone(id: nil)?.uniqueID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !perms.isGranted(permission) {
                permissionBanner
            } else {
                ForEach(list) { d in
                    PopoverRow(symbol: nil, title: d.name, checked: enabled && selectedID == d.id) { select(d) }
                }
                PopoverRow(symbol: nil, title: kind == .camera ? t("No Camera", "Sin cámara") : t("No Microphone", "Sin micrófono"), checked: !enabled) { disable() }
                if list.isEmpty {
                    Text(kind == .camera ? t("Connect a camera or choose a different device to continue.", "Conectá una cámara o elegí otro dispositivo para continuar.")
                                         : t("A microphone is required to record in this mode. Select a microphone to continue.", "Se necesita un micrófono. Conectá uno para continuar."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).padding(8)
                }
                if kind == .mic { micFooter }
                if kind == .camera && prefs.cameraEnabled { cameraOptions }
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .camera ? t("Camera access needed", "Se necesita acceso a la cámara") : t("Microphone access needed", "Se necesita acceso al micrófono"))
                .font(.system(size: 13, weight: .semibold))
            Text(kind == .camera ? t("Allow camera access in System Settings to continue.", "Permití el acceso a la cámara en Ajustes del Sistema para continuar.")
                                 : t("Allow microphone access in System Settings to continue.", "Permití el acceso al micrófono en Ajustes del Sistema para continuar."))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            Button(t("Allow access", "Permitir acceso")) { perms.request(permission) }
                .buttonStyle(PikPrimaryButtonStyle())
        }
        .foregroundStyle(.white).padding(8)
    }

    private var micFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prefs.micEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    LevelBar(level: CGFloat(audio.level))
                }
                if audio.lowVolume {
                    Label(t("Very low volume detected, try changing your microphone", "Volumen muy bajo, probá con otro micrófono"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.yellow)
                }
            }
            if AVCaptureDevice.preferredMicrophoneMode != .voiceIsolation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(.white.opacity(0.6))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("For best quality, we recommend turning on Voice Isolation", "Para mejor calidad, recomendamos activar Aislamiento de voz"))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                        Button(t("Open Microphone Controls", "Abrir controles del micrófono")) {
                            AVCaptureDevice.showSystemUserInterface(.microphoneModes)
                        }
                        .buttonStyle(PikSecondaryButtonStyle())
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.top, 6).padding(.horizontal, 4)
    }

    private var cameraOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Color.white.opacity(0.1))
            Text(t("Background effect", "Efecto de fondo")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            Picker("", selection: $prefs.cameraEffect) {
                ForEach(CameraEffect.allCases) { e in Text(e.title).tag(e) }
            }
            .labelsHidden().pickerStyle(.menu)
            if prefs.cameraEffect == .color {
                ColorPicker(t("Color", "Color"), selection: Binding(
                    get: { Theme.color(hex: prefs.cameraEffectColorHex) },
                    set: { prefs.cameraEffectColorHex = Theme.hex(of: NSColor($0)) }))
                    .font(.system(size: 12))
            }
            if prefs.cameraEffect == .image {
                BackgroundGridView(selection: $prefs.cameraEffectImageID, columns: 3, includeNone: false, includeWallpaper: false, compact: true)
            }
            HStack {
                Text(t("Shape", "Forma")).font(.system(size: 12))
                Spacer()
                Picker("", selection: $prefs.cameraShape) {
                    ForEach(CameraShape.allCases) { s in Image(systemName: s.symbol).tag(s) }
                }.pickerStyle(.segmented).frame(width: 90).labelsHidden()
            }
            Toggle(t("Mirror video", "Espejar video"), isOn: $prefs.cameraMirror).toggleStyle(.checkbox).font(.system(size: 12))
            HStack {
                Text(t("Size", "Tamaño")).font(.system(size: 12))
                Slider(value: $prefs.cameraSize, in: 120...480).controlSize(.small)
            }
        }
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.top, 2)
    }

    private func select(_ d: DeviceInfo) {
        if kind == .camera {
            prefs.cameraDeviceID = d.id; prefs.cameraEnabled = true
            CameraController.shared.start(deviceID: d.id)
            model.onCameraToggled(true)
        } else {
            prefs.micDeviceID = d.id; prefs.micEnabled = true
            AudioInputController.shared.start(deviceID: d.id)
        }
        model.popover = nil           // vuelve a la barra
    }

    private func disable() {
        if kind == .camera {
            prefs.cameraEnabled = false
            model.onCameraToggled(false)
        } else {
            prefs.micEnabled = false
            AudioInputController.shared.stop()
        }
        model.popover = nil
    }
}

struct LevelBar: View {
    var level: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(level > 0.85 ? Color.red : Color.green)
                    .frame(width: max(4, g.size.width * min(1, level * 1.3)))
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Privacidad

struct PrivacyPopover: View {
    @ObservedObject var model: ControlsModel
    @ObservedObject private var prefs = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t("Recording Privacy", "Privacidad de la grabación"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(PrivacyLevel.allCases) { p in
                PopoverRow(symbol: nil, title: p.title, subtitle: nil, checked: prefs.defaultPrivacy == p) { prefs.defaultPrivacy = p; model.popover = nil }
            }
            Text(prefs.defaultPrivacy.detail)
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 8).padding(.top, 6)
            if !prefs.sharingEnabled {
                Label(t("Links are off. Turn them on in Settings → Account.", "Los enlaces están desactivados. Activalos en Ajustes → Cuenta."), systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.yellow.opacity(0.9)).padding(8)
            }
        }
    }
}

// MARK: - Más

struct MorePopover: View {
    @ObservedObject var model: ControlsModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        switch model.morePage {
        case .menu:
            VStack(alignment: .leading, spacing: 2) {
                PopoverRow(symbol: "note.text", title: t("Speaker notes", "Notas del orador"),
                           subtitle: t("Keep notes nearby while you record", "Tené notas cerca mientras grabás"), chevron: true) {
                    model.popover = nil
                    model.onToggleNotes()
                }
                PopoverRow(symbol: "photo.on.rectangle.angled", title: t("Backgrounds", "Fondos"),
                           subtitle: t("Add a background to your recording", "Agregá un fondo a tu grabación"), chevron: true) {
                    model.morePage = .backgrounds
                }
                PopoverRow(symbol: "slider.horizontal.3", title: t("Recording settings", "Ajustes de grabación"),
                           subtitle: t("Countdown, hide dock, and more", "Cuenta regresiva, ocultar Dock y más"), chevron: true) {
                    model.morePage = .settings
                }
            }
        case .settings:
            VStack(alignment: .leading, spacing: 4) {
                backHeader(t("Recording settings", "Ajustes de grabación"))
                SwitchRow(title: t("Show recording countdown", "Mostrar cuenta regresiva"), isOn: $prefs.showCountdown)
                SwitchRow(title: t("Hide system UI", "Ocultar interfaz del sistema"), isOn: $prefs.hideSystemUI,
                          help: t("This hides the dock, menu bar, and your desktop widgets in the final recording.", "Oculta el Dock, la barra de menús y los widgets del escritorio en la grabación final."))
                SwitchRow(title: t("Hide desktop icons", "Ocultar íconos del escritorio"), isOn: $prefs.hideDesktopIcons)
                SwitchRow(title: t("Highlight mouse clicks", "Resaltar clics del mouse"), isOn: $prefs.highlightClicks)
                SwitchRow(title: t("Include system audio", "Incluir audio del sistema"), isOn: $prefs.includeSystemAudio)
                HStack {
                    Text(t("Resolution", "Resolución")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $prefs.resolution) {
                        ForEach(VideoResolution.allCases) { r in Text(r.title).tag(r) }
                    }.labelsHidden().frame(width: 110)
                }
                .padding(.horizontal, 8).foregroundStyle(.white)
                HStack {
                    Text(t("Frame rate", "Cuadros por segundo")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $prefs.fps) {
                        Text("30").tag(30); Text("60").tag(60)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 90)
                }
                .padding(.horizontal, 8).foregroundStyle(.white)
                Button { model.popover = nil; model.onOpenSettings() } label: {
                    Text(t("All settings", "Todos los ajustes")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PikSecondaryButtonStyle()).padding(.top, 6)
            }
        case .backgrounds:
            VStack(alignment: .leading, spacing: 8) {
                backHeader(t("Background styles", "Estilos de fondo"))
                Text(t("In Full Display mode, this changes your desktop background", "En modo pantalla completa, cambia el fondo de tu escritorio mientras grabás"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 8)
                BackgroundGridView(selection: $prefs.recordingBackgroundID, columns: 3, includeNone: true, includeWallpaper: true, compact: false)
                    .padding(.horizontal, 4)
                    .onChange(of: prefs.recordingBackgroundID) { _, _ in model.morePage = .menu }   // elegir un fondo vuelve al menú
            }
        }
    }

    private func backHeader(_ title: String) -> some View {
        Button { model.morePage = .menu } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cuadrícula de fondos

struct BackgroundGridView: View {
    @Binding var selection: String?
    var columns = 3
    var includeNone = true
    var includeWallpaper = true
    var compact = false
    @ObservedObject private var store = BackgroundStore.shared

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
        LazyVGrid(columns: cols, spacing: 6) {
            if includeNone {
                tile(label: t("None", "Ninguno"), selected: selection == nil, content: {
                    ZStack { Color.white.opacity(0.08); Image(systemName: "nosign").foregroundStyle(.white.opacity(0.6)) }
                }) { selection = nil }
            }
            if includeWallpaper {
                tile(label: t("Blurred background", "Fondo difuminado"), selected: selection == BackgroundStore.wallpaperBlurID, content: {
                    Image(nsImage: store.thumbnail(for: BackgroundStore.wallpaperBlurID)).resizable().scaledToFill()
                }) { selection = BackgroundStore.wallpaperBlurID }
            }
            ForEach(store.all) { b in
                tile(label: b.name, selected: selection == b.id, content: {
                    Image(nsImage: store.thumbnail(for: b.id)).resizable().scaledToFill()
                }) { selection = b.id }
                .contextMenu {
                    if b.isCustom { Button(t("Delete", "Eliminar"), role: .destructive) { store.delete(b.id) } }
                }
            }
            Button {
                if let url = pickImageFile() {
                    if let item = try? store.importImage(from: url) { selection = item.id }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    Image(systemName: "plus").foregroundStyle(.white.opacity(0.7))
                }
                .frame(height: compact ? 40 : 52)
            }
            .buttonStyle(.plain)
            .help(t("Choose an image to use as a background", "Elegí una imagen para usar de fondo"))
        }
    }

    private func tile<C: View>(label: String, selected: Bool, @ViewBuilder content: () -> C, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(height: compact ? 40 : 52)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
