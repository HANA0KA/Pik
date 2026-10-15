import AppKit
import SwiftUI

public struct PickedWindow {
    public let windowID: CGWindowID
    public let frame: CGRect          // Quartz global (origen arriba-izquierda)
    public let appName: String
    public let title: String
    public let displayID: CGDirectDisplayID
}

/// Lista de ventanas visibles para elegir (excluye ventanas propias y del sistema).
enum WindowList {
    static func candidates() -> [PickedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let skipOwners: Set<String> = ["Window Server", "Dock", "SystemUIServer", "Control Center", "Notification Center", "WindowManager"]
        var out: [PickedWindow] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let owner = w[kCGWindowOwnerName as String] as? String, !skipOwners.contains(owner),
                  let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.05,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? Int else { continue }
            let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard frame.width >= 80, frame.height >= 60 else { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            var display = CGMainDisplayID()
            var count: UInt32 = 0
            var ids = [CGDirectDisplayID](repeating: 0, count: 8)
            if CGGetDisplaysWithRect(frame, 8, &ids, &count) == .success, count > 0 { display = ids[0] }
            out.append(PickedWindow(windowID: CGWindowID(id), frame: frame, appName: owner, title: title, displayID: display))
        }
        return out
    }
}

private final class WindowPickView: NSView {
    var candidates: [PickedWindow] = []
    var hovered: PickedWindow? { didSet { if hovered?.windowID != oldValue?.windowID { needsDisplay = true } } }
    var screen: NSScreen
    var onPick: ((PickedWindow) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func localRect(_ w: PickedWindow) -> CGRect {
        let ak = ScreenGeometry.appKit(fromQuartz: w.frame)
        return ak.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    private func hit(_ p: CGPoint) -> PickedWindow? {
        candidates.first { localRect($0).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) { hovered = hit(convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {
        if let h = hit(convert(event.locationInWindow, from: nil)) { onPick?(h) }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        if let h = hovered {
            let r = localRect(h)
            ctx.addRect(bounds); ctx.addRect(r); ctx.fillPath(using: .evenOdd)
            ctx.setFillColor(Theme.nsAccent.withAlphaComponent(0.14).cgColor); ctx.fill(r)
            ctx.setStrokeColor(Theme.nsAccent.cgColor); ctx.setLineWidth(3); ctx.stroke(r.insetBy(dx: 1.5, dy: 1.5))
            let label = h.title.isEmpty ? h.appName : "\(h.appName) — \(h.title)"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
            let text = String(label.prefix(60))
            let size = (text as NSString).size(withAttributes: attrs)
            let pill = CGRect(x: r.midX - size.width / 2 - 12, y: r.midY - 14, width: size.width + 24, height: 28)
            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
            (text as NSString).draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + (28 - size.height) / 2), withAttributes: attrs)
        } else {
            ctx.fill(bounds)
            let s = t("Click a window to record it · ⎋ cancel", "Hacé clic en una ventana para grabarla · ⎋ cancelar") as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY), withAttributes: attrs)
        }
    }
}

public final class WindowPickerController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<PickedWindow?, Never>?
    private var finished = false

    public init() {}

    @MainActor
    public func pick() async -> PickedWindow? {
        finished = false
        let cands = WindowList.candidates()
        return await withCheckedContinuation { cont in
            continuation = cont
            for screen in NSScreen.screens {
                let w = OverlayWindow(screen: screen, level: PikLevel.selection)
                let v = WindowPickView(screen: screen)
                v.candidates = cands
                v.onPick = { [weak self] p in self?.finish(p) }
                v.onCancel = { [weak self] in self?.finish(nil) }
                w.contentView = v
                w.orderFrontRegardless()
                windows.append(w)
            }
            if let key = windows.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? windows.first {
                NSApp.activate(ignoringOtherApps: true)
                key.makeKeyAndOrderFront(nil)
                key.makeFirstResponder(key.contentView)
            }
        }
    }

    private func finish(_ p: PickedWindow?) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        continuation?.resume(returning: p)
        continuation = nil
    }

    public func cancel() { finish(nil) }
}

/// Con varias pantallas: elegir cuál grabar.
public final class DisplayPickerController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CGDirectDisplayID?, Never>?
    private var finished = false

    public init() {}

    @MainActor
    public func pick() async -> CGDirectDisplayID? {
        finished = false
        return await withCheckedContinuation { cont in
            continuation = cont
            for screen in NSScreen.screens {
                let w = OverlayWindow(screen: screen, level: PikLevel.selection)
                let id = screen.pikDisplayID
                let name = screen.localizedName
                w.contentView = NSHostingView(rootView: DisplayPickView(name: name, onPick: { [weak self] in self?.finish(id) }, onCancel: { [weak self] in self?.finish(nil) }))
                w.onKeyDown = { [weak self] e in
                    if e.keyCode == 53 { self?.finish(nil); return true }
                    return false
                }
                w.orderFrontRegardless()
                windows.append(w)
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func finish(_ id: CGDirectDisplayID?) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        continuation?.resume(returning: id)
        continuation = nil
    }
}

private struct DisplayPickView: View {
    let name: String
    let onPick: () -> Void
    let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 14) {
                Image(systemName: "display").font(.system(size: 44)).foregroundStyle(.white)
                Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Button(t("Record this display", "Grabar esta pantalla")) { onPick() }
                    .buttonStyle(PikPrimaryButtonStyle())
                Text(t("⎋ to cancel", "⎋ para cancelar")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
