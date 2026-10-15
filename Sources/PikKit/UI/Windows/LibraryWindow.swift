import AppKit
import SwiftUI

struct LibraryWindowView: View {
    @ObservedObject private var store = LibraryStore.shared
    @ObservedObject private var nav = LibraryNavigation.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var perms = Permissions.shared
    @State private var query = ""

    private var kinds: Set<ItemKind> {
        switch nav.tab {
        case .videos: return [.video, .meeting]      // las reuniones de versiones anteriores se ven como videos
        case .notes: return []
        }
    }

    private var items: [LibraryEntry] { store.items(of: kinds, matching: query) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 214)
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Barra lateral

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FoxLogoView(size: 30, style: .color)
                Text("Pik").font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .padding(.top, 38).padding(.bottom, 14).padding(.horizontal, 6)

            Button {
                coordinator.openControls()
            } label: {
                HStack(spacing: 6) { Image(systemName: "record.circle.fill"); Text(t("New recording", "Nueva grabación")) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PikPrimaryButtonStyle())
            .disabled(coordinator.isBusy)
            .padding(.bottom, 12)

            ForEach(LibraryTab.allCases) { tab in
                Button { nav.tab = tab } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol).frame(width: 20)
                        Text(tab.title)
                        Spacer()
                        let n = tab == .notes ? notes.notes.count : store.items(of: tabKinds(tab)).count
                        if n > 0 { Text("\(n)").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    .font(.system(size: 13, weight: nav.tab == tab ? .semibold : .regular))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(nav.tab == tab ? Theme.accent.opacity(0.16) : .clear))
                    .foregroundStyle(nav.tab == tab ? Theme.accentDeep : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            storageFooter
            Button { AppWindows.showSettings() } label: {
                HStack(spacing: 10) { Image(systemName: "gearshape").frame(width: 20); Text(t("Settings", "Ajustes")); Spacer() }
                    .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    private func tabKinds(_ tab: LibraryTab) -> Set<ItemKind> {
        switch tab {
        case .videos: return [.video, .meeting]      // las reuniones de versiones anteriores se ven como videos
        case .notes: return []
        }
    }

    private var storageFooter: some View {
        let all = store.items(of: [.video, .meeting])
        let bytes = all.reduce(Int64(0)) { $0 + $1.fileSize }
        return VStack(alignment: .leading, spacing: 2) {
            Text(t("\(all.count) videos", "\(all.count) videos")).font(.system(size: 11, weight: .medium))
            Text(Fmt.bytes(bytes)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    // MARK: Contenido

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !perms.allRequiredGranted { permissionBanner }
            if nav.tab == .videos, store.items.contains(where: { $0.recovered }) { recoveredBanner }
            if nav.tab == .notes {
                NotesLibraryView(query: query)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if items.isEmpty { emptyState } else { grid }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(nav.tab.title).font(.system(size: 22, weight: .bold)).padding(.leading, 4)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(t("Search", "Buscar"), text: $query).textFieldStyle(.plain).frame(width: 180)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
        }
        .padding(.top, 34).padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18, alignment: .top)], spacing: 22) {
            ForEach(items) { ItemCard(item: $0) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !query.isEmpty {
            EmptyStateView(title: t("No results", "Sin resultados"), detail: t("Nothing matches “\(query)”.", "Nada coincide con «\(query)»."))
        } else {
            EmptyStateView(title: t("Record your first video", "Grabá tu primer video"),
                           detail: t("Share your screen, camera and voice in seconds.", "Compartí tu pantalla, cámara y voz en segundos."),
                           buttonTitle: t("Start recording", "Empezar a grabar")) { coordinator.openControls() }
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(t("Pik needs Screen Recording permission to record.", "Pik necesita permiso de grabación de pantalla para grabar.")).font(.system(size: 12.5))
            Spacer()
            Button(t("Set up", "Configurar")) { AppWindows.showSetup() }.buttonStyle(PikSecondaryButtonStyle())
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.14))
    }

    private var recoveredBanner: some View {
        let n = store.items.filter(\.recovered).count
        return HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(Theme.accent)
            Text(t("\(n) recording(s) were recovered after Pik closed unexpectedly.", "Se recuperaron \(n) grabación(es) tras un cierre inesperado de Pik.")).font(.system(size: 12.5))
            Spacer()
            Button(t("Dismiss", "Descartar")) {
                for e in store.items where e.recovered { store.update(e.id) { $0.recovered = false } }
            }.buttonStyle(PikSecondaryButtonStyle())
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.accent.opacity(0.12))
    }
}

// MARK: - Piezas

struct ItemCard: View {
    let item: LibraryEntry
    @ObservedObject private var store = LibraryStore.shared
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(item: item)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(hover ? Theme.accent : Color.primary.opacity(0.1), lineWidth: hover ? 2 : 1))
                HStack(spacing: 4) {
                    if item.recovered { StatusPill(text: t("Recovered", "Recuperado"), symbol: "arrow.counterclockwise") }
                    if item.processing == .transcribing {
                        StatusPill(text: t("Transcribing", "Transcribiendo"), symbol: "waveform")
                    }
                    if item.isMedia { StatusPill(text: Fmt.duration(item.duration)) }
                }
                .padding(7)
            }
            .overlay(alignment: .center) {
                if hover && item.isMedia {
                    Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Circle().fill(Color.black.opacity(0.55)))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(Fmt.relative(item.createdAt)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    if item.hasCamera { Image(systemName: "person.crop.circle").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Image(systemName: item.privacy.symbol).font(.system(size: 11)).foregroundStyle(.secondary).help(item.privacy.title)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { AppWindows.showPreview(item.id) }
        .contextMenu { ItemContextMenu(item: item) }
    }
}

struct ItemContextMenu: View {
    let item: LibraryEntry

    var body: some View {
        Button(t("Open", "Abrir")) { AppWindows.showPreview(item.id) }
        Divider()
        Button(t("Copy link", "Copiar enlace")) { ItemActions.copyLink(item) }
        if item.kind == .screenshot { Button(t("Copy image", "Copiar imagen")) { ItemActions.copyImage(item) } }
        else { Button(t("Copy file", "Copiar archivo")) { ItemActions.copyFile(item) } }
        Button(t("Show in Finder", "Mostrar en Finder")) { ItemActions.reveal(item) }
        Divider()
        Button(t("Rename…", "Renombrar…")) {
            if let name = promptText(title: t("Rename", "Renombrar"), initial: item.title) { LibraryStore.shared.rename(item.id, to: name) }
        }
        Menu(t("Privacy", "Privacidad")) {
            ForEach(PrivacyLevel.allCases) { p in
                Button { LibraryStore.shared.setPrivacy(item.id, p) } label: { Label(p.title, systemImage: item.privacy == p ? "checkmark" : p.symbol) }
            }
        }
        if item.isMedia, item.transcript.isEmpty, item.processing == .none || item.processing == .failed {
            Button(t("Transcribe", "Transcribir")) { ItemActions.process(item.id) }
        }
        Divider()
        Button(t("Delete…", "Eliminar…"), role: .destructive) { ItemActions.confirmDelete(item) }
    }
}
