import AppKit
import PikKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Modo de pruebas visuales: `Pik --render-ui <carpeta>` genera PNG de las pantallas y sale.
    if let i = CommandLine.arguments.firstIndex(of: "--render-ui") {
        app.setActivationPolicy(.accessory)
        let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : NSTemporaryDirectory() + "pik-ui"
        UIPreviewRenderer.run(outputDir: URL(fileURLWithPath: dir))
        exit(0)
    }
    // `Pik --render-promo <carpeta>`: piezas reales de la interfaz (en español, con fondo transparente) para el video promocional.
    if let i = CommandLine.arguments.firstIndex(of: "--render-promo") {
        app.setActivationPolicy(.accessory)
        let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : NSTemporaryDirectory() + "pik-promo"
        UIPreviewRenderer.runPromo(outputDir: URL(fileURLWithPath: dir))
        exit(0)
    }
    if CommandLine.arguments.contains("--probe-panel") {
        app.setActivationPolicy(.accessory)
        UIPreviewRenderer.probeControlsPanel()
        exit(0)
    }
    let delegate = PikAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
