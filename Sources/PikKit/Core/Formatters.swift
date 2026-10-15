import Foundation

public enum Fmt {
    /// 83 -> "1:23", 3723 -> "1:02:03"
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: L10n.isSpanish ? "es" : "en")
        return f.localizedString(for: date, relativeTo: now)
    }

    public static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isSpanish ? "es" : "en")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Título por defecto: "Pik – 14 oct 2026 16:25"
    public static func defaultTitle(prefix: String = "Pik", date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isSpanish ? "es" : "en")
        f.dateFormat = L10n.isSpanish ? "d MMM yyyy HH:mm" : "MMM d, yyyy HH:mm"
        return "\(prefix) – \(f.string(from: date))"
    }

    /// Nombre de archivo seguro.
    public static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Pik" : String(cleaned.prefix(80))
    }
}
