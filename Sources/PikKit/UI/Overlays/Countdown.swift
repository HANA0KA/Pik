import AppKit
import SwiftUI

final class CountdownModel: ObservableObject {
    @Published var value = 3
    @Published var pulse = false
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    var body: some View {
        ZStack {
            Circle().fill(Theme.barBackground.opacity(0.88))
                .overlay(Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 3))
                .frame(width: 190, height: 190)
                .scaleEffect(model.pulse ? 1.0 : 0.92)
            Text("\(model.value)")
                .font(.system(size: 104, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(model.pulse ? 1.0 : 1.18)
                .contentTransition(.numericText())
        }
        .frame(width: 240, height: 240)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: model.pulse)
    }
}

/// Cuenta regresiva 3-2-1 centrada en la pantalla. Esc o clic la cancelan.
public final class CountdownController {
    private var window: OverlayWindow?
    private let model = CountdownModel()
    private var cancelled = false

    public init() {}

    /// Devuelve `false` si el usuario canceló.
    @MainActor
    public func run(on screen: NSScreen, seconds: Int = 3, sounds: Bool = true) async -> Bool {
        cancelled = false
        let w = OverlayWindow(screen: screen, level: PikLevel.top)
        let hosting = NSHostingView(rootView: CountdownView(model: model))
        w.contentView = hosting
        w.onKeyDown = { [weak self] e in
            if e.keyCode == 53 { self?.cancelled = true; return true }
            return false
        }
        window = w
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKey()
        defer { w.orderOut(nil); window = nil }

        for n in stride(from: seconds, through: 1, by: -1) {
            model.value = n
            model.pulse = false
            try? await Task.sleep(nanoseconds: 30_000_000)
            model.pulse = true
            SoundPlayer.shared.play(.pause, enabled: sounds)
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if cancelled { return false }
            }
        }
        return !cancelled
    }

    public func cancel() { cancelled = true }
}
