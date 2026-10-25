import AppKit
import ServiceManagement
import StatusBoardDesktop

extension BoardDelegate {
    func readLoginStatus() {
        let status = SMAppService.mainApp.status
        model.launchAtLogin = status == .enabled
        model.loginNeedsApproval = status == .requiresApproval
    }
    func selectSetting(_ index: Int) {
        model.settingsOpen = false
        guard let setting = BoardSetting(rawValue: index) else { return }
        switch setting {
        case .muteSounds:
            model.muted.toggle()
            defaults.set(model.muted, forKey: "muteSounds")
            audio.setMuted(model.muted)
        case .launchAtLogin:
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled { try service.unregister() }
                else if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                else {
                    try service.register()
                    if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                }
                readLoginStatus()
            } catch {
                readLoginStatus()
                let alert = NSAlert()
                alert.messageText = "Could not update Launch at Login"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        case .info: showInfo()
        case .quit: quit()
        }
    }
}
