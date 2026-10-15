import AppKit
import Carbon.HIToolbox
import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case openControls, startStop, pauseResume, cancelRecording
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openControls: return t("Open recording controls", "Abrir controles de grabación")
        case .startStop: return t("Start / stop recording", "Iniciar / detener grabación")
        case .pauseResume: return t("Pause / resume recording", "Pausar / reanudar grabación")
        case .cancelRecording: return t("Cancel recording", "Cancelar grabación")
        }
    }

    public var defaultShortcut: Shortcut {
        let co = UInt32(controlKey | optionKey)
        switch self {
        case .openControls: return Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: co)
        case .startStop: return Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: co)
        case .pauseResume: return Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: co)
        case .cancelRecording: return Shortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: co)
        }
    }
}

/// Atajo global: código de tecla virtual + modificadores de Carbon.
public struct Shortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Mismos modificadores en el formato de NSEvent (los usa symbolichotkeys.plist).
    public var cocoaModifierBits: Int {
        var m = 0
        if modifiers & UInt32(shiftKey) != 0 { m |= 131_072 }
        if modifiers & UInt32(controlKey) != 0 { m |= 262_144 }
        if modifiers & UInt32(optionKey) != 0 { m |= 524_288 }
        if modifiers & UInt32(cmdKey) != 0 { m |= 1_048_576 }
        return m
    }

    public var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let table: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        ]
        return table[Int(code)] ?? "#\(code)"
    }

    /// ¿Choca con algún atajo activo de macOS? (lee com.apple.symbolichotkeys)
    public func conflictsWithSystem() -> Bool {
        guard let dict = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return false }
        for (_, raw) in dict {
            guard let entry = raw as? [String: Any],
                  (entry["enabled"] as? Bool) == true,
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Any], params.count >= 3,
                  let key = (params[1] as? NSNumber)?.intValue,
                  let mods = (params[2] as? NSNumber)?.intValue else { continue }
            let masked = mods & (131_072 | 262_144 | 524_288 | 1_048_576)
            if key == Int(keyCode) && masked == cocoaModifierBits { return true }
        }
        return false
    }
}

/// Registra atajos globales con Carbon y los despacha a closures.
public final class ShortcutManager {
    public static let shared = ShortcutManager()

    public var handlers: [ShortcutAction: () -> Void] = [:]
    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private let defaults = UserDefaults.standard
    public static let didChange = Notification.Name("PikShortcutsDidChange")

    private static let signature: OSType = 0x50494B31 // 'PIK1'

    public func shortcut(for action: ShortcutAction) -> Shortcut? {
        if let data = defaults.data(forKey: "shortcut.\(action.rawValue)") {
            if data.isEmpty { return nil }   // desactivado a propósito
            if let s = try? JSONDecoder().decode(Shortcut.self, from: data) { return s }
        }
        return action.defaultShortcut
    }

    public func setShortcut(_ s: Shortcut?, for action: ShortcutAction) {
        if let s, let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: "shortcut.\(action.rawValue)")
        } else {
            defaults.set(Data(), forKey: "shortcut.\(action.rawValue)")
        }
        registerAll()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    public func reset(_ action: ShortcutAction) {
        defaults.removeObject(forKey: "shortcut.\(action.rawValue)")
        registerAll()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// ¿Otra acción de Pik ya usa este atajo?
    public func action(using s: Shortcut, excluding: ShortcutAction? = nil) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != excluding && shortcut(for: $0) == s }
    }

    /// Alternativa libre (ni de Pik ni de macOS) para "Usar atajo sugerido".
    public func suggestedShortcut(for action: ShortcutAction) -> Shortcut {
        let candidates: [UInt32] = [kVK_ANSI_K, kVK_ANSI_J, kVK_ANSI_U, kVK_ANSI_Y, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M].map { UInt32($0) }
        let mods = UInt32(controlKey | optionKey | cmdKey)
        for c in candidates {
            let s = Shortcut(keyCode: c, modifiers: mods)
            if !s.conflictsWithSystem() && self.action(using: s, excluding: action) == nil { return s }
        }
        return action.defaultShortcut
    }

    public func registerAll() {
        installHandlerIfNeeded()
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        for (i, action) in ShortcutAction.allCases.enumerated() {
            guard let s = shortcut(for: action) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i + 1))
            let status = RegisterEventHotKey(s.keyCode, s.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs[action] = ref }
            else { plogError("No se pudo registrar el atajo \(action.rawValue) (\(s.display)): \(status)") }
        }
    }

    public func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let idx = Int(hkID.id) - 1
            if idx >= 0, idx < ShortcutAction.allCases.count {
                let action = ShortcutAction.allCases[idx]
                DispatchQueue.main.async { ShortcutManager.shared.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
