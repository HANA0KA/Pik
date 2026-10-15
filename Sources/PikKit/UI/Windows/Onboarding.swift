import AppKit
import SwiftUI

enum LaunchState {
    /// ¿Estaba concedido el permiso de pantalla cuando arrancó Pik? (si se concede después, conviene reiniciar)
    static let screenAtLaunch: Bool = CGPreflightScreenCaptureAccess()
}

// MARK: - Configuración de permisos

struct SetupView: View {
    @ObservedObject private var perms = Permissions.shared

    private var needsRestart: Bool { perms.isGranted(.screen) && !LaunchState.screenAtLaunch }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                FoxLogoView(size: 64, style: .color)
                Text(t("Set up Pik", "Configurá Pik")).font(.system(size: 22, weight: .bold))
                Text(t("Pik needs a few permissions to record. Everything is processed on your Mac.",
                       "Pik necesita algunos permisos para grabar. Todo se procesa en tu Mac."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .padding(.top, 40).padding(.bottom, 14)
            ScrollView { PermissionsList().padding(.horizontal, 24) }
            Divider()
            HStack {
                if needsRestart {
                    Label(t("Restart Pik to finish enabling screen recording.", "Reiniciá Pik para terminar de activar la grabación de pantalla."), systemImage: "arrow.clockwise")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Restart Pik", "Reiniciar Pik")) { AppRelauncher.relaunch() }.buttonStyle(PikPrimaryButtonStyle())
                } else {
                    Spacer()
                    Button(perms.allRequiredGranted ? t("Done", "Listo") : t("Not now", "Ahora no")) { WindowManager.shared.close(id: "setup") }
                        .buttonStyle(PikPrimaryButtonStyle())
                }
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 600)
        .onChange(of: perms.allRequiredGranted) { _, ok in
            if ok && LaunchState.screenAtLaunch { WindowManager.shared.close(id: "setup") }
        }
    }
}

// MARK: - Bienvenida

struct OnboardingView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var perms = Permissions.shared
    @State private var step = 0
    private let last = 3

    var body: some View {
        HStack(spacing: 0) {
            sidePanel.frame(width: 250)
            VStack(spacing: 0) {
                ScrollView { stepContent.padding(32).frame(maxWidth: .infinity, alignment: .leading) }
                Divider()
                footer
            }
        }
        .frame(width: 760, height: 560)
    }

    private var sidePanel: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Spacer()
                FoxLogoView(size: 120, style: .color)
                Text("Pik").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(t("Say it with a screen.", "Decilo con una pantalla.")).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...last, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == step ? 1 : 0.4)).frame(width: i == step ? 22 : 8, height: 8)
                    }
                }
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: welcome
        case 1: permissionsStep
        case 2: preferencesStep
        default: shortcutsStep
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Welcome to Pik", "Bienvenido a Pik")).font(.system(size: 28, weight: .bold))
            Text(t("Record your screen, camera and voice in one click, then share it with a link. Pik keeps your videos on your Mac.",
                   "Grabá tu pantalla, cámara y voz con un clic y compartilo con un enlace. Pik guarda tus videos en tu Mac."))
                .font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                feature("rectangle.on.rectangle", t("Screen, window or custom area", "Pantalla, ventana o un área"), t("Pick what to share. Add your camera in a bubble.", "Elegí qué compartir. Sumá tu cámara en una burbuja."))
                feature("note.text", t("Notes & teleprompter", "Notas y teleprompter"), t("Keep your scripts and pick which one shows on screen, hidden from the video.", "Guardá tus guiones y elegí cuál ves en pantalla, sin que salga en el video."))
                feature("text.bubble", t("Transcripts", "Transcripciones"), t("Done on your Mac, in your language.", "Hechas en tu Mac, en tu idioma."))
                feature("hand.raised", t("Voice & hand gestures", "Voz y gestos"), t("Say “Pik” or show your gesture to start recording.", "Decí «Pik» o hacé tu gesto para empezar a grabar."))
            }
            .padding(.top, 8)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Allow what Pik needs", "Permití lo que Pik necesita")).font(.system(size: 24, weight: .bold))
            Text(t("Screen Recording is required. The rest are optional and you can enable them later.", "La grabación de pantalla es obligatoria. El resto es opcional y podés activarlo después."))
                .font(.system(size: 13.5)).foregroundStyle(.secondary)
            PermissionsList()
            if perms.isGranted(.screen) && !LaunchState.screenAtLaunch {
                HStack {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Theme.accent)
                    Text(t("Restart Pik so screen recording is fully active.", "Reiniciá Pik para activar del todo la grabación de pantalla.")).font(.system(size: 12.5))
                    Spacer()
                    Button(t("Restart", "Reiniciar")) { prefs.hasCompletedOnboarding = true; AppRelauncher.relaunch() }.buttonStyle(PikPrimaryButtonStyle())
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Make it yours", "Hacelo tuyo")).font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Your name", "Tu nombre")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField("", text: $prefs.userName).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Who can open your videos by default?", "¿Quién puede abrir tus videos por defecto?")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("", selection: $prefs.defaultPrivacy) { ForEach(PrivacyLevel.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.radioGroup).labelsHidden()
                Text(prefs.defaultPrivacy.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("After you stop recording", "Cuando dejás de grabar")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("", selection: $prefs.afterRecording) { ForEach(AfterRecordingAction.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize()
            }
            Toggle(t("Transcribe my recordings automatically", "Transcribir mis grabaciones automáticamente"), isOn: $prefs.autoTranscribe)
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Shortcuts to remember", "Atajos para recordar")).font(.system(size: 24, weight: .bold))
            Text(t("Use them from any app. You can change them in Settings.", "Usalos desde cualquier app. Podés cambiarlos en Ajustes.")).font(.system(size: 13.5)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(ShortcutAction.allCases) { a in
                    HStack {
                        Text(a.title).font(.system(size: 13))
                        Spacer()
                        Text(ShortcutManager.shared.shortcut(for: a)?.display ?? "—")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    }
                    .padding(.vertical, 8)
                    if a != ShortcutAction.allCases.last { Divider() }
                }
            }
            .padding(.horizontal, 14).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            Text(t("Pik lives in your menu bar. Click the fox for more.", "Pik vive en tu barra de menús. Tocá el zorrito para ver más.")).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button(t("Back", "Atrás")) { step -= 1 }.buttonStyle(PikSecondaryButtonStyle()) }
            Spacer()
            if step == 1, !perms.allRequiredGranted {
                Button(t("Skip for now", "Omitir por ahora")) { step += 1 }.buttonStyle(PikSecondaryButtonStyle())
            }
            if step < last {
                Button(t("Continue", "Continuar")) { step += 1 }.buttonStyle(PikPrimaryButtonStyle())
            } else {
                Button(t("Start recording", "Empezar a grabar")) { finish(record: true) }.buttonStyle(PikPrimaryButtonStyle(recording: false))
                Button(t("Finish", "Terminar")) { finish(record: false) }.buttonStyle(PikSecondaryButtonStyle())
            }
        }
        .padding(16)
    }

    @MainActor private func finish(record: Bool) {
        prefs.hasCompletedOnboarding = true
        WindowManager.shared.close(id: "onboarding")
        if record { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppCoordinator.shared.openControls() } }
    }
}
