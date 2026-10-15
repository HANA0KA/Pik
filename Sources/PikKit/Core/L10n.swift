import Foundation
import NaturalLanguage

/// Textos bilingües: `t("Record", "Grabar")`. El idioma sale de la preferencia o, por defecto, del idioma del sistema.
public enum L10n {
    public static var override: String? = nil   // "es" | "en" | nil (sistema)

    /// Primer idioma de la lista del sistema que Pik traduce (español o inglés); si no hay, inglés.
    public static func systemLanguage(preferred: [String] = Locale.preferredLanguages) -> String {
        for id in preferred {
            if id.hasPrefix("es") { return "es" }
            if id.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    public static var language: String { override ?? systemLanguage() }
    public static var isSpanish: Bool { language == "es" }

    /// Idioma de voz del sistema con su región (p. ej. es-MX), para reconocimiento y dictado.
    public static var systemLocale: Locale { Locale(identifier: Locale.preferredLanguages.first ?? "en-US") }

    /// Configuración regional para reconocer voz en `lang` («es» o «en»): la variante que el usuario ya tiene en el sistema o una por defecto.
    public static func speechLocale(for lang: String, preferred: [String] = Locale.preferredLanguages) -> Locale {
        if let id = preferred.first(where: { $0.hasPrefix(lang) }) { return Locale(identifier: id) }
        return Locale(identifier: lang == "es" ? "es-ES" : "en-US")
    }

    public static func name(of lang: String) -> String { lang == "es" ? "Español" : "English" }
}

@inline(__always)
public func t(_ en: String, _ es: String) -> String {
    L10n.isSpanish ? es : en
}

/// Distingue si un texto transcrito está en español o en inglés.
public enum SpokenLanguage {
    /// Probabilidad (0…1) de que `text` esté en `lang` («es» o «en»), entre esos dos idiomas.
    public static func probability(of lang: String, in text: String) -> Double {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.spanish, .english]
        r.processString(text)
        let h = r.languageHypotheses(withMaximum: 2)
        return h[lang == "es" ? .spanish : .english] ?? 0
    }
}
