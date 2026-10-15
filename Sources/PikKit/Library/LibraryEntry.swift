import Foundation

public struct TranscriptSegment: Codable, Equatable, Identifiable {
    public var id: Int
    public var start: TimeInterval
    public var duration: TimeInterval
    public var text: String
    public init(id: Int, start: TimeInterval, duration: TimeInterval, text: String) {
        self.id = id; self.start = start; self.duration = duration; self.text = text
    }
}

public enum ProcessingState: String, Codable {
    case none, transcribing, failed
    /// Valor que versiones anteriores podían guardar; se lee como «sin procesar».
    case summarizing
}

/// Elemento de la biblioteca: video, captura, reunión o dictado.
public struct LibraryEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    public var createdAt: Date
    /// Ruta absoluta del archivo (video o imagen). Los dictados no tienen archivo.
    public var filePath: String?
    public var duration: TimeInterval
    public var width: Int
    public var height: Int
    public var fileSize: Int64
    public var mode: RecordingMode?
    public var hasCamera: Bool
    public var hasMic: Bool
    public var hasSystemAudio: Bool
    public var privacy: PrivacyLevel
    public var shareToken: String
    public var transcript: [TranscriptSegment]
    public var text: String?                 // dictados
    public var meetingTitle: String?
    public var meetingURL: String?
    public var processing: ProcessingState
    public var recovered: Bool
    public var inProgress: Bool              // true mientras se graba (para recuperación tras un cierre inesperado)

    public init(id: UUID = UUID(), kind: ItemKind, title: String, createdAt: Date = Date(),
                filePath: String? = nil, duration: TimeInterval = 0, width: Int = 0, height: Int = 0,
                fileSize: Int64 = 0, mode: RecordingMode? = nil, hasCamera: Bool = false, hasMic: Bool = false,
                hasSystemAudio: Bool = false, privacy: PrivacyLevel = .onlyMe, text: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.createdAt = createdAt
        self.filePath = filePath; self.duration = duration; self.width = width; self.height = height
        self.fileSize = fileSize; self.mode = mode; self.hasCamera = hasCamera; self.hasMic = hasMic
        self.hasSystemAudio = hasSystemAudio; self.privacy = privacy
        self.shareToken = Self.makeToken()
        self.transcript = []; self.text = text
        self.meetingTitle = nil; self.meetingURL = nil
        self.processing = .none; self.recovered = false; self.inProgress = false
    }

    public var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }
    public var thumbnailURL: URL { Storage.thumbnailsFolder.appendingPathComponent("\(id.uuidString).jpg") }
    public var transcriptText: String { transcript.map(\.text).joined(separator: " ") }
    public var isMedia: Bool { kind == .video || kind == .meeting }

    public static func makeToken() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<14).map { _ in alphabet.randomElement()! })
    }

    public var searchBlob: String {
        [title, meetingTitle ?? "", text ?? "", transcriptText].joined(separator: " ").lowercased()
    }
}
