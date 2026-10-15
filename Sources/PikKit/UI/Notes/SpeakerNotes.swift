import AppKit
import SwiftUI

/// NSTextView con teleprompter: puede desplazarse sola a velocidad constante.
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrolling: Bool
    var speed: Double          // puntos por segundo
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.font = .systemFont(ofSize: fontSize, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.string = text
        context.coordinator.textView = tv
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tv = context.coordinator.textView!
        if tv.string != text { tv.string = text }
        if tv.font?.pointSize != fontSize { tv.font = .systemFont(ofSize: fontSize, weight: .regular) }
        context.coordinator.parent = self
        context.coordinator.setScrolling(scrolling)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        weak var textView: NSTextView?
        weak var scroll: NSScrollView?
        private var timer: Timer?
        private var lastTick = Date()

        init(_ p: NotesTextView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func setScrolling(_ on: Bool) {
            if on, timer == nil {
                lastTick = Date()
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer!, forMode: .common)
            } else if !on {
                timer?.invalidate(); timer = nil
            }
        }

        private func tick() {
            let now = Date()
            let dt = now.timeIntervalSince(lastTick); lastTick = now
            guard let scroll, let doc = scroll.documentView else { return }
            let clip = scroll.contentView
            var o = clip.bounds.origin
            let maxY = max(0, doc.frame.height - clip.bounds.height)
            o.y = min(maxY, o.y + CGFloat(parent.speed * dt))
            clip.scroll(to: o)
            scroll.reflectScrolledClipView(clip)
            if o.y >= maxY { DispatchQueue.main.async { self.parent.scrolling = false } }
        }

        deinit { timer?.invalidate() }
    }
}

struct SpeakerNotesView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var store = NotesStore.shared
    @State private var scrolling = false
    var onClose: () -> Void

    private var text: Binding<String> {
        Binding(get: { store.active?.text ?? "" },
                set: { if let id = store.activeID { store.update(id, text: $0) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            ZStack(alignment: .topLeading) {
                NotesTextView(text: text, scrolling: $scrolling, speed: prefs.teleprompterSpeed, fontSize: 17)
                if (store.active?.text ?? "").isEmpty {
                    Text(t("Start typing your notes…", "Empezá a escribir tus notas…"))
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 15).padding(.vertical, 10).allowsHitTesting(false)
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            footer
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 360, height: 440)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panelBackground.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.barStroke))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(20)
        .onAppear { store.ensureActive() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text").foregroundStyle(Theme.accent)
            Menu {
                ForEach(store.notes) { note in
                    Button { store.setActive(note.id) } label: {
                        if note.id == store.activeID { Label(note.displayTitle, systemImage: "checkmark") } else { Text(note.displayTitle) }
                    }
                }
                Divider()
                Button { let n = store.add(title: t("New note", "Nueva nota")); store.setActive(n.id) } label: { Label(t("New note", "Nueva nota"), systemImage: "plus") }
                Button { AppWindows.showLibrary(tab: .notes) } label: { Label(t("Manage notes…", "Administrar notas…"), systemImage: "list.bullet") }
            } label: {
                Text(store.active?.displayTitle ?? t("Notes", "Notas")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(t("Choose which note appears on screen", "Elegí qué nota aparece en pantalla"))
            Spacer()
            Button { scrolling.toggle() } label: { Image(systemName: scrolling ? "pause.fill" : "play.fill") }
                .buttonStyle(PillIconButtonStyle(selected: scrolling, size: 28))
                .help(t("Auto-scroll (teleprompter)", "Desplazamiento automático (teleprompter)"))
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(PillIconButtonStyle(size: 28)).help(t("Hide speaker notes", "Ocultar notas del orador"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Text(t("Notes hidden in video", "Notas ocultas en el video")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(t("Teleprompter speed", "Velocidad")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Slider(value: $prefs.teleprompterSpeed, in: 8...90).frame(width: 90).controlSize(.mini)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

public final class SpeakerNotesController {
    private var host: PanelHost?
    public var onVisibilityChange: ((Bool) -> Void)?

    public init() {}

    public var isVisible: Bool { host?.panel.isVisible == true }
    public var windowNumber: Int? { host?.panel.windowNumber }

    public func toggle(on screen: NSScreen) { isVisible ? hide() : show(on: screen) }

    public func show(on screen: NSScreen) {
        if host == nil {
            host = PanelHost(level: PikLevel.notes, allowsKey: true, excludedFromCapture: true, anchor: .topLeading) {
                SpeakerNotesView(onClose: { [weak self] in self?.hide() })
            }
        }
        guard let host else { return }
        let vf = screen.visibleFrame
        let s = host.size == .zero ? CGSize(width: 400, height: 480) : host.size
        host.show(at: CGPoint(x: vf.maxX - s.width - 12, y: vf.maxY - s.height - 12))
        Preferences.shared.showNotes = true
        onVisibilityChange?(true)
    }

    public func hide() {
        host?.close()
        Preferences.shared.showNotes = false
        onVisibilityChange?(false)
    }

    public func destroy() { host?.close(); host = nil }
}
