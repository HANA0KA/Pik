import SwiftUI

/// Pestaña «Notas» de la biblioteca: lista de notas, editor y botón para elegir cuál se muestra en pantalla al grabar.
struct NotesLibraryView: View {
    let query: String
    @ObservedObject private var store = NotesStore.shared
    @State private var selection: UUID?

    private var notes: [Note] { store.filtered(query) }
    private var selected: Note? { selection.flatMap { store.note(id: $0) } ?? store.active ?? store.notes.first }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 270)
            Divider()
            Group {
                if let note = selected { NoteEditor(note: note, isActive: note.id == store.activeID, onDelete: { delete(note) }) .id(note.id) }
                else { emptyState }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = store.activeID ?? store.notes.first?.id } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("\(store.notes.count) notes", "\(store.notes.count) notas")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { selection = store.add(title: t("New note", "Nueva nota")).id } label: { Label(t("New note", "Nueva nota"), systemImage: "plus") }
                    .buttonStyle(PikPrimaryButtonStyle())
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(notes) { note in
                        NoteRow(note: note, selected: note.id == selected?.id, isActive: note.id == store.activeID,
                                onSelect: { selection = note.id }, onShow: { store.setActive(note.id) })
                            .contextMenu {
                                Button(t("Show on screen", "Mostrar en pantalla")) { store.setActive(note.id) }
                                Divider()
                                Button(t("Delete", "Eliminar"), role: .destructive) { delete(note) }
                            }
                    }
                    if notes.isEmpty && !store.notes.isEmpty {
                        Text(t("No results", "Sin resultados")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(t("Write your first note", "Escribí tu primera nota")).font(.system(size: 18, weight: .semibold))
            Text(t("Keep scripts and talking points here. Pick which one appears on screen while you record — only you see it, it never shows in the video.",
                   "Guardá acá guiones y puntos a decir. Elegí cuál aparece en pantalla mientras grabás: solo vos la ves, no sale en el video."))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button { selection = store.add(title: t("New note", "Nueva nota")).id } label: { Label(t("New note", "Nueva nota"), systemImage: "plus") }
                .buttonStyle(PikPrimaryButtonStyle())
        }
        .padding(32)
    }

    private func delete(_ note: Note) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("Delete “\(note.displayTitle)”?", "¿Eliminar «\(note.displayTitle)»?")
        alert.informativeText = t("This note will be removed.", "Esta nota se eliminará.")
        alert.addButton(withTitle: t("Delete", "Eliminar"))
        alert.addButton(withTitle: t("Cancel", "Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.delete(note.id)
        selection = store.activeID
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    let isActive: Bool
    var onSelect: () -> Void
    var onShow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if isActive { StatusPill(text: t("On screen", "En pantalla"), symbol: "rectangle.inset.filled.and.person.filled", tint: Theme.accent) }
                }
                Text(note.snippet.isEmpty ? t("Empty", "Vacía") : note.snippet)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                Text(Fmt.dateTime(note.updatedAt)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button(action: onShow) { Image(systemName: isActive ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.plain).foregroundStyle(isActive ? Theme.accent : Color.secondary)
                .help(isActive ? t("This note appears on screen", "Esta nota aparece en pantalla") : t("Show this note on screen", "Mostrar esta nota en pantalla"))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accent.opacity(0.16) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct NoteEditor: View {
    let note: Note
    let isActive: Bool
    var onDelete: () -> Void
    @ObservedObject private var store = NotesStore.shared
    @State private var title: String
    @State private var text: String

    init(note: Note, isActive: Bool, onDelete: @escaping () -> Void) {
        self.note = note; self.isActive = isActive; self.onDelete = onDelete
        _title = State(initialValue: note.title); _text = State(initialValue: note.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(t("Title", "Título"), text: $title)
                .textFieldStyle(.plain).font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
                .onChange(of: title) { _, v in store.update(note.id, title: v) }
            Divider().padding(.horizontal, 22)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14.5)).scrollContentBackground(.hidden)
                    .padding(.horizontal, 17).padding(.vertical, 8)
                    .onChange(of: text) { _, v in store.update(note.id, text: v) }
                if text.isEmpty {
                    Text(t("Write what you want to say…", "Escribí lo que querés decir…"))
                        .font(.system(size: 14.5)).foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text(t("\(note.wordCount) words", "\(note.wordCount) palabras")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(PikSecondaryButtonStyle()).help(t("Delete", "Eliminar"))
                if isActive {
                    Label(t("Shown on screen", "Se muestra en pantalla"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accentDeep)
                } else {
                    Button { store.setActive(note.id) } label: { Label(t("Show on screen", "Mostrar en pantalla"), systemImage: "rectangle.inset.filled.and.person.filled") }
                        .buttonStyle(PikPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }
}
