import AVFoundation
import SwiftUI

/// Vista previa de la cámara (espejada, como un espejo).
struct HandCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
        v.layer = layer
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Esqueleto de la mano sobre la vista previa (para que veas que Pik la está viendo).
struct HandSkeleton: View {
    let shape: HandShape?
    var tint: Color = .white
    private static let bones: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11), (11, 12),
        (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (17, 18), (18, 19), (19, 20), (0, 17),
    ]
    var body: some View {
        Canvas { ctx, size in
            guard let s = shape, s.isValid else { return }
            // Vision: origen abajo-izquierda; la vista previa va espejada.
            let pt: (CGPoint) -> CGPoint = { CGPoint(x: (1 - $0.x) * size.width, y: (1 - $0.y) * size.height) }
            var path = Path()
            for (a, b) in Self.bones { path.move(to: pt(s.points[a])); path.addLine(to: pt(s.points[b])) }
            ctx.stroke(path, with: .color(tint.opacity(0.9)), lineWidth: 2.5)
            for p in s.points { let c = pt(p); ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(tint)) }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
final class GestureRecorderModel: ObservableObject {
    enum Step: Equatable {
        case ready
        case countdown(Int)
        case capturing
        case captured(HandShape)
        case failed(String)
    }

    let action: GestureAction
    @Published var step: Step = .ready
    @Published var conflictText: String?
    @Published var recognized = false
    private let service = HandGestureService.shared
    private let owner = "recorder-\(UUID().uuidString)"
    private let collected = Collector()
    private var candidate: HandShape?
    private var task: Task<Void, Never>?

    /// Acumula cuadros desde el hilo de vídeo.
    final class Collector {
        private let lock = NSLock()
        private var active = false
        private var shapes: [HandShape] = []
        private var misses = 0
        private var test: HandShape?
        var onTestMatch: ((Bool) -> Void)?
        func begin() { lock.lock(); active = true; shapes = []; misses = 0; lock.unlock() }
        func end() -> (shapes: [HandShape], misses: Int) { lock.lock(); active = false; let r = (shapes, misses); lock.unlock(); return r }
        func setTest(_ s: HandShape?) { lock.lock(); test = s; lock.unlock() }
        func feed(_ s: HandShape?) {
            lock.lock()
            if active { if let s { shapes.append(s) } else { misses += 1 } }
            let t = test
            lock.unlock()
            if let t { onTestMatch?(s.map { GestureMatcher.matches($0, t) } ?? false) }
        }
    }

    init(action: GestureAction) { self.action = action }

    func open() {
        GestureController.shared.suspend()
        collected.onTestMatch = { [weak self] ok in DispatchQueue.main.async { self?.recognized = ok } }
        service.request(owner: owner, deviceID: Preferences.shared.cameraDeviceID) { [collected] in collected.feed($0) }
    }

    private var closed = false
    func close() {
        guard !closed else { return }
        closed = true
        task?.cancel()
        service.release(owner: owner)
        GestureController.shared.resume()
    }

    func start() {
        task?.cancel()
        conflictText = nil; recognized = false; collected.setTest(nil)
        task = Task { [weak self] in
            guard let self else { return }
            for n in stride(from: 3, through: 1, by: -1) {
                self.step = .countdown(n)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            self.step = .capturing
            self.collected.begin()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let r = self.collected.end()
            if Task.isCancelled { return }
            guard r.shapes.count >= 10, r.misses <= r.shapes.count / 3 else {
                self.step = .failed(t("I couldn't see your hand clearly. Show it fully, with good light, and hold it still.",
                                      "No vi bien tu mano. Mostrala completa, con buena luz, y mantenela quieta."))
                return
            }
            guard let avg = GestureMatcher.average(r.shapes) else {
                self.step = .failed(t("Your hand moved too much. Hold the gesture still for 2 seconds.", "La mano se movió demasiado. Mantené el gesto quieto 2 segundos."))
                return
            }
            candidate = avg
            if let other = GestureStore.shared.conflict(for: avg, excluding: action) {
                conflictText = t("It looks a lot like your “\(other.action.title)” gesture. Pick a more different one so they aren't confused.",
                                 "Se parece mucho a tu gesto de «\(other.action.title)». Elegí uno más distinto para que no se confundan.")
            }
            collected.setTest(avg)
            step = .captured(avg)
        }
    }

    func save() {
        guard let candidate else { return }
        GestureStore.shared.set(candidate, for: action)
        ToastPresenter.shared.show(title: t("Gesture saved", "Gesto guardado"), symbol: "hand.raised.fill", duration: 2)
    }
}

struct GestureRecorderView: View {
    @StateObject private var model: GestureRecorderModel
    @ObservedObject private var service = HandGestureService.shared
    let onClose: () -> Void

    init(action: GestureAction, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: GestureRecorderModel(action: action))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(model.action.title).font(.system(size: 17, weight: .semibold))
            ZStack {
                HandCameraPreview(session: service.session)
                HandSkeleton(shape: service.liveShape, tint: model.recognized ? .green : .white)
                if case .countdown(let n) = model.step {
                    Text("\(n)").font(.system(size: 90, weight: .bold)).foregroundStyle(.white).shadow(radius: 8)
                }
                if model.step == .capturing {
                    VStack { Spacer(); Text(t("Hold it…", "Mantenelo…")).font(.system(size: 15, weight: .semibold)).padding(8)
                        .background(Capsule().fill(Theme.rec)).foregroundStyle(.white).padding(10) }
                }
                if model.recognized {
                    VStack { HStack { Spacer(); Label(t("Recognized", "Reconocido"), systemImage: "checkmark.circle.fill")
                        .padding(8).background(Capsule().fill(Color.green)).foregroundStyle(.white).padding(10) }; Spacer() }
                }
            }
            .frame(width: 480, height: 360)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let f = service.failure { Text(f).font(.system(size: 12.5)).foregroundStyle(.red) }
            instructions
            controls
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { model.open() }
        .onDisappear { model.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
            if (n.object as? NSWindow)?.identifier?.rawValue == "gesture-recorder" { model.close() }
        }
    }

    @ViewBuilder private var instructions: some View {
        switch model.step {
        case .ready:
            Text(t("Put one hand in front of the camera, pick a pose you can repeat easily (for example ✌️, ✋ or 👍) and press Start. You'll have 3 seconds.",
                   "Poné una mano frente a la cámara, elegí una pose fácil de repetir (por ejemplo ✌️, ✋ o 👍) y apretá Empezar. Tendrás 3 segundos."))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .countdown, .capturing:
            Text(t("Keep your hand still and fully visible.", "Mantené la mano quieta y completamente visible.")).font(.system(size: 13)).foregroundStyle(.secondary)
        case .captured:
            VStack(spacing: 6) {
                Text(t("Got it. Try repeating the gesture: if it turns green, Pik recognizes it.", "Listo. Probá repetir el gesto: si se pone verde, Pik lo reconoce."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let c = model.conflictText { Text(c).font(.system(size: 12.5)).foregroundStyle(.orange).multilineTextAlignment(.center) }
            }
        case .failed(let m):
            Text(m).font(.system(size: 13)).foregroundStyle(.red).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            Button(t("Cancel", "Cancelar")) { onClose() }
            switch model.step {
            case .ready, .failed:
                Button(model.step == .ready ? t("Start", "Empezar") : t("Try again", "Reintentar")) { model.start() }.keyboardShortcut(.defaultAction)
            case .countdown, .capturing:
                Button(t("Start", "Empezar")) {}.disabled(true)
            case .captured:
                Button(t("Repeat", "Repetir")) { model.start() }
                Button(t("Save gesture", "Guardar gesto")) { model.save(); onClose() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
