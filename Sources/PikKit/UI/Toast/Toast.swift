import AppKit
import SwiftUI

public struct ToastAction: Identifiable {
    public let id = UUID()
    public var title: String
    public var symbol: String?
    public var handler: () -> Void
    public init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.handler = handler
    }
}

final class ToastModel: ObservableObject {
    @Published var title: String
    @Published var subtitle: String?
    @Published var image: NSImage?
    @Published var symbol: String?
    @Published var actions: [ToastAction]
    var dismiss: () -> Void = {}
    init(title: String, subtitle: String?, image: NSImage?, symbol: String?, actions: [ToastAction]) {
        self.title = title; self.subtitle = subtitle; self.image = image; self.symbol = symbol; self.actions = actions
    }
}

struct ToastView: View {
    @ObservedObject var model: ToastModel
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = model.image {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack { Theme.accent.opacity(0.2); Image(systemName: model.symbol ?? "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent) }
                }
            }
            .frame(width: 88, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(model.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let s = model.subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
                HStack(spacing: 6) {
                    ForEach(model.actions) { a in
                        Button { a.handler(); model.dismiss() } label: {
                            HStack(spacing: 4) {
                                if let s = a.symbol { Image(systemName: s).font(.system(size: 10, weight: .semibold)) }
                                Text(a.title).font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { model.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(PillIconButtonStyle(size: 22)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.barBackground.opacity(0.96))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.barStroke)))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .padding(20)
    }
}

/// Aviso flotante abajo a la derecha (grabación terminada, captura tomada, errores…).
public final class ToastPresenter {
    public static let shared = ToastPresenter()
    private var host: PanelHost?
    private var model: ToastModel?
    private var dismissWork: DispatchWorkItem?

    public func show(title: String, subtitle: String? = nil, image: NSImage? = nil, symbol: String? = nil,
                     actions: [ToastAction] = [], duration: TimeInterval = 7) {
        DispatchQueue.main.async {
            self.dismissNow()
            let m = ToastModel(title: title, subtitle: subtitle, image: image, symbol: symbol, actions: actions)
            m.dismiss = { [weak self] in self?.dismissNow() }
            let h = PanelHost(level: PikLevel.top, excludedFromCapture: true, anchor: .bottomCenter) { ToastView(model: m) }
            self.host = h; self.model = m
            let screen = ScreenGeometry.screenUnderMouse()
            let vf = screen.visibleFrame
            let s = h.size == .zero ? CGSize(width: 420, height: 100) : h.size
            h.show(at: CGPoint(x: vf.maxX - s.width - 4, y: vf.minY + 4))
            let w = DispatchWorkItem { [weak self] in self?.dismissNow() }
            self.dismissWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
        }
    }

    public func dismissNow() {
        dismissWork?.cancel()
        host?.close(); host = nil; model = nil
    }
}
