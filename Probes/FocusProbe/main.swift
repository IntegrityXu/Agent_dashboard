import AppKit
import Intents
import UserNotifications

// Isolated public-API capability test. Never schedules a notification or sound.
@MainActor
final class FocusProbe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let label = NSTextField(wrappingLabelWithString: "正在读取权限…")
    var notificationAuthorization = -1
    var soundSetting = -1
    var timer: Timer?
    var previous = ""
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 440, height: 230),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Status Board · Focus API 验证"
        window.isReleasedWhenClosed = false
        let request = NSButton(title: "授权通知与 Focus", target: self, action: #selector(authorize))
        let quit = NSButton(title: "退出验证", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let note = NSTextField(wrappingLabelWithString: "独立能力探针 · 只申请权限和读取状态\n不会发送通知、播放声音或修改专注设置。")
        let stack = NSStackView(views: [note, label, request, quit])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)
        ])
        print("communicationCapabilityDeclared=true; no notifications scheduled"); fflush(stdout)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }
    @objc func authorize() {
        // Explicit button click; request only sound authorization, not banners.
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound]) { [weak self] granted, error in
            let failed = error != nil
            Task { @MainActor in
                print("notificationPermission granted=\(granted) error=\(failed)"); fflush(stdout)
                _ = await INFocusStatusCenter.default.requestAuthorization()
                self?.sample()
            }
        }
    }
    func sample() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let authorization = settings.authorizationStatus.rawValue
            let sound = settings.soundSetting.rawValue
            Task { @MainActor in
                self?.notificationAuthorization = authorization
                self?.soundSetting = sound
                self?.render()
            }
        }
    }
    func render() {
        let center = INFocusStatusCenter.default
        let value = center.focusStatus.isFocused.map(String.init) ?? "unknown"
        let line = "focusAuthorization=\(center.authorizationStatus.rawValue) focused=\(value) notificationAuthorization=\(notificationAuthorization) soundSetting=\(soundSetting)"
        label.stringValue = "Focus 授权：\(center.authorizationStatus.rawValue) · 状态：\(value)\n通知授权：\(notificationAuthorization) · 声音权限：\(soundSetting)"
        if line != previous { print("\(Date().ISO8601Format()) \(line)"); fflush(stdout); previous = line }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = FocusProbe()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
