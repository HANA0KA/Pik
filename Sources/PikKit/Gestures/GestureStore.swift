import Combine
import Foundation

/// Gestos guardados por el usuario (uno por acción), en `gestures.json` dentro de la carpeta de datos de Pik.
public final class GestureStore: ObservableObject {
    public static let shared = GestureStore()
    @Published public private(set) var templates: [GestureTemplate] = []
    private let url: URL

    public init(url: URL = Storage.appSupport.appendingPathComponent("gestures.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url), let t = try? JSONDecoder().decode([GestureTemplate].self, from: data) {
            templates = t.filter { $0.shape.isValid }
        }
    }

    public func template(for action: GestureAction) -> GestureTemplate? { templates.first { $0.action == action } }

    /// Guarda (o reemplaza) el gesto de una acción.
    public func set(_ shape: HandShape, for action: GestureAction) {
        templates.removeAll { $0.action == action }
        templates.append(GestureTemplate(action: action, shape: shape))
        save()
    }

    public func remove(_ action: GestureAction) {
        templates.removeAll { $0.action == action }
        save()
    }

    /// Otro gesto ya guardado que se parezca demasiado a `shape` (para avisar antes de confundirlos).
    public func conflict(for shape: HandShape, excluding action: GestureAction) -> GestureTemplate? {
        templates.first { tpl in
            tpl.action != action && GestureMatcher.matches(shape, tpl.shape, sensitivity: 1.4)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(templates) { try? data.write(to: url, options: .atomic) }
    }
}
