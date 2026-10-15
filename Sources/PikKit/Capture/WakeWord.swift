import Foundation

/// Detecta la palabra de activación «Pik» en texto reconocido. Como es una palabra inventada y muy corta, el
/// reconocedor la suele escribir de otra forma («Pi», «Big», «Vic», «pick»…). Para no dispararse con frases normales:
/// - las grafías casi seguras («pik», «pic», «pick»…) valen en cualquier parte;
/// - las dudosas («big», «vic», «peak»…) solo valen si lo dicho es una frase cortísima («Pik» → «Big.») o va
///   precedido de un saludo («oye Pik» → «oye Vic»).
public enum WakeWord {
    static let strict: Set<String> = ["pik", "pic", "pick", "pike", "pique", "pyk", "piq"]
    static let loose: Set<String> = ["pi", "pii", "pe", "big", "vic", "bic", "bick", "peek", "peak", "pig", "beck", "vick", "pit", "pip", "bik"]
    /// Cualquier otra «p/b/v/f + i/ee/ea/y + k/c/g/t/p» («Pi», «Beak», «Fick»…): el reconocedor corta o cambia la consonante final.
    private static let looseShape = try! NSRegularExpression(pattern: "^[pbvf](i{1,2}|ee|ea|y)(ck|k|c|g|t|p)$")
    private static func isLoose(_ w: String) -> Bool {
        loose.contains(w) || looseShape.firstMatch(in: w, range: NSRange(w.startIndex..., in: w)) != nil
    }
    static let greetings: Set<String> = ["hey", "hi", "ok", "okay", "oye", "ey", "eh", "hola", "ola"]

    /// Cierto si el texto contiene la palabra de activación según las reglas de arriba.
    public static func matches(_ text: String) -> Bool {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: strict.contains) { return true }
        if words.count <= 2, words.contains(where: isLoose) { return true }
        for (i, w) in words.enumerated() where i > 0 && isLoose(w) && greetings.contains(words[i - 1]) { return true }
        return false
    }
}

/// Evita disparos repetidos: tras activarse, ignora la palabra un tiempo.
struct WakeCooldown {
    private var last = Date.distantPast
    let interval: TimeInterval
    init(interval: TimeInterval = 4) { self.interval = interval }
    mutating func fire(now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
