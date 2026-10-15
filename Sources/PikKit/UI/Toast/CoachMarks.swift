import AppKit
import SwiftUI

final class CoachModel: ObservableObject {
    @Published var step = 0
    var dismiss: () -> Void = {}
}

struct CoachMarkView: View {
    @ObservedObject var model: CoachModel

    private var steps: [(String, String, String)] {
        let sc = ShortcutManager.shared.shortcut(for: .startStop)?.display ?? "⌃⌥R"
        return [
            ("rectangle.on.rectangle", t("Choose what to record", "Elegí qué grabar"),
             t("Your whole screen, one window, a custom area or just your camera.", "Toda la pantalla, una ventana, un área o solo tu cámara.")),
            ("person.crop.circle", t("Add your camera and voice", "Sumá tu cámara y tu voz"),
             t("Turn on the camera bubble and pick your microphone.", "Activá la burbuja de cámara y elegí tu micrófono.")),
            ("record.circle.fill", t("Press Record", "Apretá Grabar"),
             t("Or use \(sc) from any app. Pik counts down 3, 2, 1.", "O usá \(sc) desde cualquier app. Pik cuenta 3, 2, 1.")),
        ]
    }

    var body: some View {
        let s = steps[min(model.step, steps.count - 1)]
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: s.0).font(.system(size: 18)).foregroundStyle(Theme.accent)
                    Text(s.1).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(model.step + 1)/\(steps.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                }
                Text(s.2).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(t("Skip", "Omitir")) { model.dismiss() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button(model.step < steps.count - 1 ? t("Next", "Siguiente") : t("Got it", "Entendido")) {
                        if model.step < steps.count - 1 { model.step += 1 } else { model.dismiss() }
                    }
                    .buttonStyle(PikPrimaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(14).frame(width: 330)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.barBackground)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5)))
            Triangle().fill(Theme.barBackground).frame(width: 18, height: 9)
                .overlay(Triangle().stroke(Theme.accent.opacity(0.7), lineWidth: 1.5).mask(Rectangle().padding(.top, 1)))
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .padding(20)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Consejos de primer uso sobre la barra de controles (una sola vez).
@MainActor
public final class CoachMarkController {
    public static let shared = CoachMarkController()
    private var host: PanelHost?

    public func showIfNeeded(above panel: NSPanel) {
        let prefs = Preferences.shared
        guard !prefs.hasSeenCoachMarks, host == nil else { return }
        prefs.hasSeenCoachMarks = true
        let model = CoachModel()
        model.dismiss = { [weak self] in self?.dismiss() }
        let h = PanelHost(level: PikLevel.modal, excludedFromCapture: true, anchor: .bottomCenter) { CoachMarkView(model: model) }
        host = h
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak panel] in
            guard let self, let panel, let h = self.host else { return }
            let s = h.size == .zero ? CGSize(width: 370, height: 170) : h.size
            h.show(at: CGPoint(x: panel.frame.midX - s.width / 2, y: panel.frame.maxY - 18))
        }
    }

    public func dismiss() { host?.close(); host = nil }
}
