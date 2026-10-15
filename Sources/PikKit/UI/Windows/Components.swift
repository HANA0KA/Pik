import AppKit
import SwiftUI

// MARK: - Utilidades

enum AppRelauncher {
    /// Cierra Pik y lo vuelve a abrir (hace falta tras dar el permiso de grabación de pantalla).
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

@MainActor
func promptText(title: String, message: String = "", initial: String, ok: String = t("Save", "Guardar")) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    field.stringValue = initial
    alert.accessoryView = field
    alert.addButton(withTitle: ok)
    alert.addButton(withTitle: t("Cancel", "Cancelar"))
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return v.isEmpty ? nil : v
}

// MARK: - Permisos

struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.title).font(.system(size: 13, weight: .semibold))
                    if kind.isRequired { Text(t("Required", "Obligatorio")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent) }
                }
                Text(kind.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if state == .granted {
                Label(t("Allowed", "Permitido"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else {
                Button(state == .notDetermined ? t("Allow", "Permitir") : t("Open Settings", "Abrir Ajustes"), action: action)
                    .buttonStyle(PikSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }
}

struct PermissionsList: View {
    @ObservedObject private var perms = Permissions.shared
    var kinds: [PermissionKind] = PermissionKind.allCases

    var body: some View {
        VStack(spacing: 4) {
            ForEach(kinds) { k in
                PermissionRow(kind: k, state: perms.state(k)) { perms.request(k) }
                if k != kinds.last { Divider().opacity(0.5) }
            }
        }
        .onAppear { perms.refresh(); perms.startPolling() }
    }
}

// MARK: - Estados vacíos y miniaturas

struct EmptyStateView: View {
    var title: String
    var detail: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            FoxLogoView(size: 84, style: .color).opacity(0.95)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            if let buttonTitle, let action {
                Button(action: action) {
                    HStack(spacing: 6) { Image(systemName: "record.circle.fill"); Text(buttonTitle) }
                }
                .buttonStyle(PikPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct ThumbnailView: View {
    let item: LibraryEntry
    @ObservedObject private var store = LibraryStore.shared
    @State private var requested = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            if let img = store.thumbnail(for: item) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: item.kind == .screenshot ? "photo" : "play.rectangle").font(.system(size: 26)).foregroundStyle(.secondary)
                    .onAppear {
                        guard !requested else { return }
                        requested = true
                        store.makeThumbnail(for: item)
                    }
            }
        }
        .clipped()
    }
}

struct StatusPill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .black.opacity(0.65)
    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(tint))
    }
}

struct PrivacyMenu: View {
    let current: PrivacyLevel
    var onChange: (PrivacyLevel) -> Void

    var body: some View {
        Menu {
            ForEach(PrivacyLevel.allCases) { p in
                Button { onChange(p) } label: {
                    Label(p.title, systemImage: current == p ? "checkmark" : p.symbol)
                }
            }
        } label: {
            Label(current.title, systemImage: current.symbol).font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(current.detail)
    }
}

extension NSImage {
    /// Reduce a un ancho máximo (para vistas previas pesadas).
    func downscaled(maxWidth: CGFloat) -> NSImage {
        guard size.width > maxWidth else { return self }
        let f = maxWidth / size.width
        let ns = NSSize(width: maxWidth, height: size.height * f)
        let out = NSImage(size: ns)
        out.lockFocus(); draw(in: NSRect(origin: .zero, size: ns)); out.unlockFocus()
        return out
    }
}
