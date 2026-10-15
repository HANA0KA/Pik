import AppKit
import Foundation
import UniformTypeIdentifiers

/// Acciones comunes sobre elementos de la biblioteca (las usan toast, menú, biblioteca y vista previa).
@MainActor
public enum ItemActions {
    @discardableResult
    public static func copyLink(_ item: LibraryEntry, silent: Bool = false) -> Bool {
        let share = ShareServer.shared
        guard Preferences.shared.sharingEnabled, let url = share.link(for: item) else {
            if !silent {
                ToastPresenter.shared.show(title: t("Sharing is turned off", "Compartir está desactivado"),
                                           subtitle: t("Turn it on in Settings › Account.", "Activalo en Ajustes › Cuenta."), symbol: "link.badge.plus",
                                           actions: [ToastAction(t("Open Settings", "Abrir Ajustes")) { AppWindows.showSettings(tab: .account) }])
            }
            return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        pb.setString(url.absoluteString, forType: .URL)
        if !silent {
            let sub = item.privacy == .onlyMe
                ? t("Only you can open it. Change privacy to share.", "Solo vos podés abrirlo. Cambiá la privacidad para compartir.")
                : t("Anyone on your network can open it.", "Cualquiera en tu red puede abrirlo.")
            ToastPresenter.shared.show(title: t("Link copied", "Enlace copiado"), subtitle: sub, symbol: "link", duration: 4)
        }
        return true
    }

    public static func copyFile(_ item: LibraryEntry, silent: Bool = false) {
        guard let url = item.fileURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        if !silent { ToastPresenter.shared.show(title: t("File copied", "Archivo copiado"), symbol: "doc.on.doc", duration: 3) }
    }

    public static func copyImage(_ item: LibraryEntry, silent: Bool = false) {
        guard let url = item.fileURL, let img = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        if !silent { ToastPresenter.shared.show(title: t("Image copied", "Imagen copiada"), image: img, duration: 3) }
    }

    public static func copyText(_ text: String, message: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ToastPresenter.shared.show(title: message, symbol: "doc.on.clipboard", duration: 2.5)
    }

    public static func reveal(_ item: LibraryEntry) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func open(_ item: LibraryEntry) { AppWindows.showPreview(item.id) }

    /// Borra el elemento (archivo a la papelera) tras confirmar.
    @discardableResult
    public static func confirmDelete(_ item: LibraryEntry, in window: NSWindow? = nil) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("Delete “\(item.title)”?", "¿Eliminar «\(item.title)»?")
        alert.informativeText = t("The file will be moved to the Trash.", "El archivo se moverá a la papelera.")
        alert.addButton(withTitle: t("Delete", "Eliminar"))
        alert.addButton(withTitle: t("Cancel", "Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        LibraryStore.shared.delete(item.id, trashFile: true)
        return true
    }

    public static func share(_ item: LibraryEntry, from view: NSView) {
        guard let url = item.fileURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: Procesamiento (transcripción)

    private static var running = Set<UUID>()

    /// Transcribe en segundo plano y guarda el resultado en la biblioteca.
    public static func process(_ id: UUID, language: String? = nil) {
        guard !running.contains(id), let item = LibraryStore.shared.item(id: id), let url = item.fileURL, item.isMedia else { return }
        guard item.hasMic || item.hasSystemAudio else { return }
        running.insert(id)
        LibraryStore.shared.update(id) { $0.processing = .transcribing }
        Task {
            defer { Task { @MainActor in running.remove(id) } }
            do {
                let segs = try await Transcriber.shared.transcribe(fileURL: url, language: language ?? Preferences.shared.transcriptionLanguage)
                await MainActor.run { LibraryStore.shared.update(id) { $0.transcript = segs; $0.processing = .none } }
            } catch {
                plogError("Transcripción falló: \(error.localizedDescription)")
                await MainActor.run { LibraryStore.shared.update(id) { $0.processing = .failed } }
            }
        }
    }

    public static var isProcessing: Bool { !running.isEmpty }
}
