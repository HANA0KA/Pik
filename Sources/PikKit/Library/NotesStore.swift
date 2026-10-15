import Foundation

/// Nota de texto (guion, puntos a decir…) que se puede mostrar en pantalla mientras se graba.
public struct Note: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var text: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, text: String = "", updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.text = text; self.updatedAt = updatedAt
    }

    /// Título para listas: el escrito o, si está vacío, la primera línea del texto.
    public var displayTitle: String {
        let own = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? t("Untitled note", "Nota sin título") : String(first.prefix(60))
    }

    public var snippet: String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    public var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// Notas del usuario y cuál de ellas aparece en pantalla (se guardan en notes.json).
public final class NotesStore: ObservableObject {
    public static let shared = NotesStore(legacyText: UserDefaults.standard.string(forKey: "notesText"))

    @Published public private(set) var notes: [Note] = []
    /// La nota que se muestra en pantalla al grabar.
    @Published public private(set) var activeID: UUID?

    private struct File: Codable { var notes: [Note]; var activeID: UUID? }

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    /// `legacyText`: el texto único de versiones anteriores; si no hay archivo todavía, pasa a ser la primera nota.
    public init(fileURL: URL = Storage.notesJSON, legacyText: String? = nil) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data) {
            notes = file.notes
            activeID = file.activeID
        } else if let legacy = legacyText?.trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            let note = Note(title: t("Speaker notes", "Notas del orador"), text: legacy)
            notes = [note]; activeID = note.id
            saveNow()
        }
        if activeID == nil || !notes.contains(where: { $0.id == activeID }) { activeID = notes.first?.id }
    }

    public var active: Note? { notes.first { $0.id == activeID } }
    public func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    public func filtered(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter { ($0.title + " " + $0.text).lowercased().contains(q) }
    }

    @discardableResult
    public func add(title: String = "", text: String = "") -> Note {
        let note = Note(title: title, text: text)
        notes.insert(note, at: 0)
        if activeID == nil { activeID = note.id }
        saveNow()
        return note
    }

    /// Cambia el título y/o el texto; el guardado en disco se junta para no escribir en cada tecla.
    public func update(_ id: UUID, title: String? = nil, text: String? = nil) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var n = notes[i]
        if let title, title != n.title { n.title = title }
        if let text, text != n.text { n.text = text }
        guard n != notes[i] else { return }
        n.updatedAt = Date()
        notes[i] = n
        saveSoon()
    }

    public func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if activeID == id { activeID = notes.first?.id }
        saveNow()
    }

    public func setActive(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }), activeID != id else { return }
        activeID = id
        saveNow()
    }

    /// Para mostrar notas en pantalla siempre hay una donde escribir.
    @discardableResult
    public func ensureActive() -> Note {
        if let a = active { return a }
        return add(title: t("My notes", "Mis notas"))
    }

    // MARK: Disco

    private func saveSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    public func saveNow() {
        saveWork?.cancel(); saveWork = nil
        guard let data = try? JSONEncoder().encode(File(notes: notes, activeID: activeID)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
