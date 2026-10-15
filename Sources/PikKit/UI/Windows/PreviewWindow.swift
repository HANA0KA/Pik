import AVFoundation
import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modelo del reproductor

@MainActor
final class PreviewModel: ObservableObject {
    let itemID: UUID
    let player = AVPlayer()
    weak var playerView: AVPlayerView?
    @Published var time: TimeInterval = 0
    @Published var busy: String?
    @Published var progress: Double?
    @Published var errorText: String?
    private var observer: Any?
    /// Solo para capturas de pantalla (`--render-promo`): fija el instante de reproducción mostrado.
    static var previewTimeOverride: TimeInterval?
    /// Solo para capturas de pantalla (`--render-promo`): muestra la pestaña «Detalles» con un enlace de ejemplo (sin datos reales del equipo).
    static var promoLink: String?

    init(itemID: UUID) {
        self.itemID = itemID
        if let t = Self.previewTimeOverride { time = t }
        reload()
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.time = t.seconds.isFinite ? t.seconds : 0 }
        }
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
    }

    var item: LibraryEntry? { LibraryStore.shared.item(id: itemID) }

    func reload() {
        guard let url = item?.fileURL else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    // MARK: Recorte

    func trim() {
        guard let view = playerView, view.canBeginTrimming else {
            errorText = t("This video can't be trimmed.", "Este video no se puede recortar."); return
        }
        player.pause()
        view.beginTrimming { [weak self] result in
            Task { @MainActor in
                guard let self, result == .okButton, let current = self.player.currentItem, let url = self.item?.fileURL else { return }
                let full = current.duration
                let start = current.reversePlaybackEndTime.isValid ? current.reversePlaybackEndTime : .zero
                let end = current.forwardPlaybackEndTime.isValid ? current.forwardPlaybackEndTime : full
                guard CMTimeCompare(end, start) > 0, !(CMTimeCompare(start, .zero) == 0 && CMTimeCompare(end, full) >= 0) else { return }
                await self.applyTrim(url: url, start: start, end: end)
            }
        }
    }

    private func applyTrim(url: URL, start: CMTime, end: CMTime) async {
        busy = t("Trimming…", "Recortando…")
        defer { busy = nil }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".pik-trim-\(UUID().uuidString).mp4")
        do {
            try await MediaExport.exportRange(url, start: start, end: end, to: tmp)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let hadTranscript = !(item?.transcript.isEmpty ?? true)
            LibraryStore.shared.update(itemID) {
                $0.duration = dur; $0.fileSize = Int64(size); $0.transcript = []
            }
            if let it = item { LibraryStore.shared.makeThumbnail(for: it) }
            reload()
            if hadTranscript { ItemActions.process(itemID) }
            ToastPresenter.shared.show(title: t("Video trimmed", "Video recortado"), subtitle: Fmt.duration(dur), symbol: "scissors", duration: 3)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            errorText = error.localizedDescription
        }
    }

    // MARK: Exportar

    func exportMP4() {
        guard let it = item, let url = it.fileURL, let dest = MediaExport.savePanel(name: it.title + ".mp4", type: .mpeg4Movie) else { return }
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        catch { errorText = error.localizedDescription }
    }

    func exportAudio() {
        guard let it = item, let url = it.fileURL, let dest = MediaExport.savePanel(name: it.title + ".m4a", type: .mpeg4Audio) else { return }
        Task {
            busy = t("Exporting audio…", "Exportando audio…")
            defer { busy = nil }
            do { try await MediaExport.exportAudio(url, to: dest); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
            catch { errorText = error.localizedDescription }
        }
    }

    func exportGIF() {
        guard let it = item, let url = it.fileURL, let dest = MediaExport.savePanel(name: it.title + ".gif", type: .gif) else { return }
        Task {
            busy = t("Creating GIF…", "Creando GIF…"); progress = 0
            defer { busy = nil; progress = nil }
            do {
                try await MediaExport.exportGIF(url, to: dest) { [weak self] p in Task { @MainActor in self?.progress = p } }
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch { errorText = error.localizedDescription }
        }
    }

    func exportSRT() {
        guard let it = item, !it.transcript.isEmpty, let dest = MediaExport.savePanel(name: it.title + ".srt", type: UTType(filenameExtension: "srt") ?? .plainText) else { return }
        try? MediaExport.srt(it.transcript).write(to: dest, atomically: true, encoding: .utf8)
    }
}

struct PikPlayerView: NSViewRepresentable {
    let model: PreviewModel
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = model.player
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        v.allowsPictureInPicturePlayback = false
        model.playerView = v
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// MARK: - Ventana

struct PreviewWindowView: View {
    let itemID: UUID
    @ObservedObject private var store = LibraryStore.shared

    var body: some View {
        if let item = store.item(id: itemID) {
            switch item.kind {
            case .video, .meeting: VideoPreview(itemID: itemID, kind: item.kind)
            case .screenshot, .dictation: EmptyView()
            }
        } else {
            EmptyStateView(title: t("This item was deleted", "Este elemento se eliminó"), detail: "")
                .onAppear { WindowManager.shared.close(id: "preview-\(itemID.uuidString)") }
        }
    }
}

// MARK: - Video / reunión

private enum InspectorTab: String, CaseIterable, Identifiable {
    case transcript, info
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transcript: return t("Transcript", "Transcripción")
        case .info: return t("Details", "Detalles")
        }
    }
}

struct VideoPreview: View {
    let itemID: UUID
    let kind: ItemKind
    @StateObject private var model: PreviewModel
    @ObservedObject private var store = LibraryStore.shared
    @State private var tab: InspectorTab = .transcript
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    init(itemID: UUID, kind: ItemKind) {
        self.itemID = itemID; self.kind = kind
        _model = StateObject(wrappedValue: PreviewModel(itemID: itemID))
        _tab = State(initialValue: PreviewModel.promoLink == nil ? .transcript : .info)
    }

    private var item: LibraryEntry? { store.item(id: itemID) }

    var body: some View {
        if let item {
            HStack(spacing: 0) {
                main(item).frame(minWidth: 480)
                Divider()
                inspector(item).frame(width: 340)
            }
            .onAppear { title = item.title }
            .alert(t("Something went wrong", "Algo salió mal"), isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.errorText ?? "") }
        }
    }

    // MARK: Columna principal

    private func main(_ item: LibraryEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(t("Title", "Título"), text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { _, f in if !f { commitTitle() } }
                PrivacyMenu(current: item.privacy) { store.setPrivacy(item.id, $0) }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)

            ZStack {
                Color.black
                PikPlayerView(model: model)
                if let busy = model.busy {
                    VStack(spacing: 10) {
                        if let p = model.progress { ProgressView(value: p).frame(width: 160) } else { ProgressView() }
                        Text(busy).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    }
                    .padding(20).background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.7)))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            actionBar(item).padding(14)
            Spacer(minLength: 0)
        }
    }

    private func commitTitle() {
        let v = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { title = item?.title ?? ""; return }
        if v != item?.title { store.rename(itemID, to: v) }
    }

    private func actionBar(_ item: LibraryEntry) -> some View {
        HStack(spacing: 8) {
            Button { ItemActions.copyLink(item) } label: { Label(t("Copy link", "Copiar enlace"), systemImage: "link") }
                .buttonStyle(PikPrimaryButtonStyle())
            Button { ItemActions.copyFile(item) } label: { Label(t("Copy file", "Copiar archivo"), systemImage: "doc.on.doc") }
                .buttonStyle(PikSecondaryButtonStyle())
            if let url = item.fileURL {
                ShareLink(item: url) { Label(t("Share", "Compartir"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(PikSecondaryButtonStyle())
            }
            Button { model.trim() } label: { Label(t("Trim", "Recortar"), systemImage: "scissors") }
                .buttonStyle(PikSecondaryButtonStyle())
            Menu {
                Button(t("Save a copy (MP4)…", "Guardar una copia (MP4)…")) { model.exportMP4() }
                Button(t("Animated GIF…", "GIF animado…")) { model.exportGIF() }
                Button(t("Audio only (M4A)…", "Solo audio (M4A)…")) { model.exportAudio() }
            } label: { Label(t("Export", "Exportar"), systemImage: "square.and.arrow.down") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Button { ItemActions.reveal(item) } label: { Image(systemName: "folder") }
                .buttonStyle(PikSecondaryButtonStyle()).help(t("Show in Finder", "Mostrar en Finder"))
            Button {
                if ItemActions.confirmDelete(item) { WindowManager.shared.close(id: "preview-\(itemID.uuidString)") }
            } label: { Image(systemName: "trash") }
                .buttonStyle(PikSecondaryButtonStyle()).help(t("Delete", "Eliminar"))
        }
    }

    // MARK: Inspector

    private func inspector(_ item: LibraryEntry) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(12)
            Divider()
            switch tab {
            case .transcript: TranscriptPane(item: item, time: model.time, seek: model.seek, exportSRT: model.exportSRT)
            case .info: InfoPane(item: item)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
    }
}

private struct TranscriptPane: View {
    let item: LibraryEntry
    let time: TimeInterval
    let seek: (TimeInterval) -> Void
    let exportSRT: () -> Void
    @State private var query = ""

    private var segments: [TranscriptSegment] {
        query.isEmpty ? item.transcript : item.transcript.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if item.processing == .transcribing {
            VStack(spacing: 10) { ProgressView(); Text(t("Transcribing on your Mac…", "Transcribiendo en tu Mac…")).font(.system(size: 12.5)).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.transcript.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(item.hasMic || item.hasSystemAudio
                     ? t("No transcript yet", "Todavía no hay transcripción")
                     : t("This video has no audio", "Este video no tiene audio")).font(.system(size: 14, weight: .semibold))
                if item.processing == .failed { Text(t("The last attempt failed. Check Speech Recognition permission.", "El último intento falló. Revisá el permiso de reconocimiento de voz.")).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if item.hasMic || item.hasSystemAudio {
                    Button(t("Transcribe", "Transcribir")) { ItemActions.process(item.id) }.buttonStyle(PikPrimaryButtonStyle())
                    Menu(t("Choose language", "Elegir idioma")) {
                        Button(t("Automatic (Spanish / English)", "Automático (español / inglés)")) { ItemActions.process(item.id, language: "auto") }
                        Button("Español") { ItemActions.process(item.id, language: "es") }
                        Button("English") { ItemActions.process(item.id, language: "en") }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(t("Search transcript", "Buscar en la transcripción"), text: $query).textFieldStyle(.plain)
                    Menu {
                        Button(t("Copy transcript", "Copiar transcripción")) { ItemActions.copyText(item.transcriptText, message: t("Transcript copied", "Transcripción copiada")) }
                        Button(t("Export subtitles (.srt)…", "Exportar subtítulos (.srt)…")) { exportSRT() }
                        Divider()
                        Menu(t("Transcribe again", "Transcribir de nuevo")) {
                            Button(t("Automatic (Spanish / English)", "Automático (español / inglés)")) { ItemActions.process(item.id, language: "auto") }
                            Button("Español") { ItemActions.process(item.id, language: "es") }
                            Button("English") { ItemActions.process(item.id, language: "en") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(segments) { seg in
                                let active = time >= seg.start && time < seg.start + max(seg.duration, 0.5)
                                Button { seek(seg.start) } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(Fmt.duration(seg.start)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Theme.accentDeep).frame(width: 42, alignment: .leading)
                                        Text(seg.text).font(.system(size: 13)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.accent.opacity(0.18) : .clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(seg.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: time) { _, now in
                        guard query.isEmpty, let cur = item.transcript.last(where: { $0.start <= now }) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(cur.id, anchor: .center) }
                    }
                }
            }
        }
    }
}

struct InfoPane: View {
    let item: LibraryEntry

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(v).font(.system(size: 12.5)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row(t("Created", "Creado"), Fmt.dateTime(item.createdAt))
                if item.isMedia { row(t("Duration", "Duración"), Fmt.duration(item.duration)) }
                if item.width > 0 { row(t("Resolution", "Resolución"), "\(item.width) × \(item.height)") }
                row(t("Size", "Tamaño"), Fmt.bytes(item.fileSize))
                if let m = item.mode { row(t("Mode", "Modo"), m.title) }
                if item.isMedia {
                    let audio = [item.hasMic ? t("Microphone", "Micrófono") : nil, item.hasSystemAudio ? t("System audio", "Audio del sistema") : nil].compactMap { $0 }
                    row(t("Audio", "Audio"), audio.isEmpty ? t("None", "Ninguno") : audio.joined(separator: ", "))
                    row(t("Camera", "Cámara"), item.hasCamera ? t("Yes", "Sí") : t("No", "No"))
                }
                row(t("Privacy", "Privacidad"), item.privacy.title)
                if let p = item.filePath { row(t("File", "Archivo"), PreviewModel.promoLink != nil ? "~/Movies/Pik/\(item.title).mp4" : (p as NSString).abbreviatingWithTildeInPath) }
                Divider().padding(.vertical, 4)
                shareSection
            }
            .padding(16)
        }
    }

    @ViewBuilder private var shareSection: some View {
        let share = ShareServer.shared
        if let sample = PreviewModel.promoLink {
            Text(t("Share link", "Enlace para compartir")).font(.system(size: 12, weight: .semibold))
            Text(sample).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
            Text(item.privacy.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(t("Links work while Pik is open on this Mac and on the same network.", "Los enlaces funcionan mientras Pik esté abierto en este Mac y en la misma red."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else if let link = share.link(for: item) {
            Text(t("Share link", "Enlace para compartir")).font(.system(size: 12, weight: .semibold))
            Text(link.absoluteString).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
            if let lan = share.lanLink(for: item) {
                Text(lan.absoluteString).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(item.privacy.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(t("Links work while Pik is open on this Mac and on the same network.", "Los enlaces funcionan mientras Pik esté abierto en este Mac y en la misma red."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text(t("Link sharing is off. Turn it on in Settings › Account.", "Compartir por enlace está desactivado. Activalo en Ajustes › Cuenta.")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
