import Foundation
import ServiceManagement

public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            plogError("No se pudo cambiar 'abrir al iniciar sesión': \(error.localizedDescription)")
        }
    }
}
