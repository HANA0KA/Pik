import AppKit
import Combine
import SwiftUI

public final class HUDModel: ObservableObject {
    @Published public var drawEnabled = false
    @Published public var drawColorIndex = 0
    @Published public var persistentStrokes = false
    @Published public var notesVisible = false
    @Published public var warning: String?

    public static let drawColors: [NSColor] = [
        Theme.nsRec, Theme.nsAccent, .systemYellow, .systemGreen, .systemBlue, .white,
    ]

    public var onStop: () -> Void = {}
    public var onTogglePause: () -> Void = {}
    public var onRestart: () -> Void = {}
    public var onDelete: () -> Void = {}
    public var onToggleDraw: (Bool) -> Void = { _ in }
    public var onColor: (NSColor) -> Void = { _ in }
    public var onClearDrawing: () -> Void = {}
    public var onTogglePersistence: (Bool) -> Void = { _ in }
    public var onToggleNotes: () -> Void = {}

    public init() {}
}

/// Barra vertical que se muestra mientras grabás (no sale en el video).
struct RecordingHUDView: View {
    @ObservedObject var model: HUDModel
    @ObservedObject private var engine = RecordingEngine.shared
    @ObservedObject private var audio = AudioInputController.shared
    @State private var blink = false
    /// Solo para capturas de pantalla: fija el estado del parpadeo del punto REC.
    var blinkOverride: Bool? = nil

    private var paused: Bool { engine.phase == .paused }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            pill
            if model.drawEnabled { drawPalette.transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity)) }
        }
        .environment(\.colorScheme, .dark)
        .padding(22)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.drawEnabled)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { blink = true } }
    }

    private var pill: some View {
        VStack(spacing: 6) {
            Button { model.onStop() } label: {
                ZStack {
                    Circle().fill(Theme.rec)
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 14, height: 14)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .help(t("Stop recording", "Detener grabación"))

            VStack(spacing: 2) {
                Text(Fmt.duration(engine.elapsed))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Circle().fill(paused ? Color.yellow : Theme.rec).frame(width: 6, height: 6).opacity(paused ? 1 : ((blinkOverride ?? blink) ? 1 : 0.3))
                    Text(paused ? t("Paused", "Pausa") : "REC").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.vertical, 2)

            Divider().overlay(Color.white.opacity(0.12)).frame(width: 30)

            hudButton(paused ? "play.fill" : "pause.fill", help: paused ? t("Resume recording", "Reanudar grabación") : t("Pause recording", "Pausar grabación")) { model.onTogglePause() }
            hudButton("arrow.counterclockwise", help: t("Restart recording", "Reiniciar grabación")) { model.onRestart() }
            hudButton("trash", help: t("Delete recording", "Eliminar grabación")) { model.onDelete() }
            hudButton("pencil.tip", help: t("Draw on screen", "Dibujar en pantalla"), selected: model.drawEnabled) {
                model.drawEnabled.toggle(); model.onToggleDraw(model.drawEnabled)
            }
            hudButton("note.text", help: t("Speaker notes", "Notas del orador"), selected: model.notesVisible) { model.onToggleNotes() }

            if model.warning != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    .help(model.warning ?? "")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(width: 64)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Theme.barBackground.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.barStroke))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        )
    }

    private func hudButton(_ symbol: String, help: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(PillIconButtonStyle(selected: selected, size: 38))
        .help(help)
        .accessibilityLabel(help)
    }

    private var drawPalette: some View {
        HStack(spacing: 8) {
            ForEach(Array(HUDModel.drawColors.enumerated()), id: \.offset) { i, c in
                Button {
                    model.drawColorIndex = i
                    model.onColor(c)
                } label: {
                    Circle().fill(Color(nsColor: c)).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(.white, lineWidth: model.drawColorIndex == i ? 2.5 : 0.5))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 18)
            Button { model.persistentStrokes.toggle(); model.onTogglePersistence(model.persistentStrokes) } label: {
                Image(systemName: model.persistentStrokes ? "pin.fill" : "pin")
            }
            .buttonStyle(PillIconButtonStyle(selected: model.persistentStrokes, size: 28))
            .help(t("Keep strokes on screen", "Mantener trazos en pantalla"))
            Button { model.onClearDrawing() } label: { Image(systemName: "eraser") }
                .buttonStyle(PillIconButtonStyle(size: 28)).help(t("Clear drawing", "Borrar dibujo"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Theme.barBackground.opacity(0.95)).overlay(Capsule().stroke(Theme.barStroke)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

public final class RecordingHUDController {
    public let model = HUDModel()
    private var host: PanelHost?

    public init() {}

    public var windowNumber: Int? { host?.panel.windowNumber }

    public func show(on screen: NSScreen) {
        if host == nil {
            host = PanelHost(level: PikLevel.controls, excludedFromCapture: true, anchor: .bottomLeading) {
                RecordingHUDView(model: self.model)
            }
        }
        guard let host else { return }
        let vf = screen.visibleFrame
        host.show(at: CGPoint(x: vf.minX + 6, y: vf.minY + 6))
    }

    public func hide() {
        host?.close()
        host = nil
    }
}
