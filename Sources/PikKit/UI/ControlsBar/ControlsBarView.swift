import AppKit
import SwiftUI

/// Barra flotante previa a grabar: modos, cámara, micrófono, privacidad, más y el botón de grabar.
public struct ControlsBarView: View {
    @ObservedObject var model: ControlsModel
    @ObservedObject private var prefs = Preferences.shared

    // Medidas fijas (para que los popovers apunten a su botón).
    static let barWidth: CGFloat = 542
    static let barHeight: CGFloat = 64
    private let popoverWidth: CGFloat = 300

    public init(model: ControlsModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let p = model.popover {
                popoverView(p)
                    .frame(width: popoverWidth)
                    .padding(.leading, popoverX(p))
            }
            bar
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 26)
        .fixedSize()
    }

    // MARK: Barra

    private var bar: some View {
        HStack(spacing: 4) {
            Button { model.onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PillIconButtonStyle(size: 40))
            .help(t("Close", "Cerrar"))
            .accessibilityLabel(t("Close", "Cerrar"))

            HStack(spacing: 4) {
                ForEach(RecordingMode.allCases) { m in
                    Button {
                        prefs.mode = m
                        model.onModeChange(m)
                    } label: {
                        Image(systemName: m.symbol).font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(PillIconButtonStyle(selected: prefs.mode == m, size: 36))
                    .help(m.title)
                    .accessibilityLabel(m.title)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            toggleButton(symbol: prefs.cameraEnabled ? "video.fill" : "video.slash", on: prefs.cameraEnabled,
                         active: model.popover == .camera, help: t("Camera", "Cámara")) { model.toggle(.camera) }
            toggleButton(symbol: prefs.micEnabled ? "mic.fill" : "mic.slash", on: prefs.micEnabled,
                         active: model.popover == .mic, help: t("Microphone", "Micrófono")) { model.toggle(.mic) }
            toggleButton(symbol: prefs.defaultPrivacy.symbol, on: true,
                         active: model.popover == .privacy, help: t("Recording Privacy", "Privacidad de la grabación")) { model.toggle(.privacy) }
            toggleButton(symbol: "ellipsis", on: true, active: model.popover == .more, help: t("More", "Más")) { model.toggle(.more) }

            Button { model.onRecord() } label: {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                    Text(t("Record", "Grabar"))
                }
                .frame(width: 91, height: 40)
                .background(Capsule().fill(Theme.accent))
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(model.isStarting ? 0.6 : 1)
            .disabled(model.isStarting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .frame(width: Self.barWidth, height: Self.barHeight)
        .background(
            Capsule().fill(Theme.barBackground.opacity(0.95))
                .overlay(Capsule().stroke(Theme.barStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
    }

    private func toggleButton(symbol: String, on: Bool, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .opacity(on ? 1 : 0.55)
        }
        .buttonStyle(PillIconButtonStyle(selected: active, size: 40))
        .help(help)
        .accessibilityLabel(help)
    }

    // Centro horizontal de cada botón dentro de la barra.
    private func popoverX(_ p: ControlsModel.Popover) -> CGFloat {
        let center: CGFloat
        switch p {
        case .camera: center = 240
        case .mic: center = 284
        case .privacy: center = 328
        case .more: center = 372
        }
        return max(0, min(Self.barWidth - popoverWidth, center - popoverWidth / 2))
    }

    @ViewBuilder
    private func popoverView(_ p: ControlsModel.Popover) -> some View {
        Group {
            switch p {
            case .camera: DeviceListPopover(kind: .camera, model: model)
            case .mic: DeviceListPopover(kind: .mic, model: model)
            case .privacy: PrivacyPopover(model: model)
            case .more: MorePopover(model: model)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.barBackground.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.barStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
    }
}
