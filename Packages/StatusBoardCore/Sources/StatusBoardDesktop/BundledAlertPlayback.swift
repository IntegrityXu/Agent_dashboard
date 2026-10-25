import AppKit
import StatusBoardCore

/// One player at a time; completion drives the queue. No notification banners,
/// app activation, volume override or system Focus-state assumption.
@MainActor
public final class BundledAlertPlayback: NSObject, AlertPlayback, NSSoundDelegate {
    private var sound: NSSound?
    private var completion: (@MainActor () -> Void)?
    private var watchdog: Timer?
    public override init() { super.init() }
    public static func assetURL(for kind: AlertKind) -> URL? {
        Bundle.module.url(forResource: kind.rawValue, withExtension: "wav")
    }
    public func play(_ kind: AlertKind, completion: @escaping @MainActor () -> Void) -> Bool {
        stop()
        guard let url = Self.assetURL(for: kind), let sound = NSSound(contentsOf: url, byReference: false) else { return false }
        self.sound = sound; self.completion = completion; sound.delegate = self
        guard sound.play() else { stop(); return false }
        let identifier = ObjectIdentifier(sound)
        // Normally the delegate fires in under one second. A lost device or
        // callback cannot indefinitely block the rest of the notification queue.
        let timer = Timer(timeInterval: max(2, sound.duration + 1), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish(identifier) }
        }
        watchdog = timer; RunLoop.main.add(timer, forMode: .common)
        return true
    }
    public func stop() {
        watchdog?.invalidate(); watchdog = nil
        completion = nil
        sound?.delegate = nil; sound?.stop(); sound = nil
    }
    private func finish(_ identifier: ObjectIdentifier) {
        guard let sound, ObjectIdentifier(sound) == identifier else { return }
        let callback = completion
        stop(); callback?()
    }
    nonisolated public func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        let identifier = ObjectIdentifier(sound)
        Task { @MainActor [weak self] in self?.finish(identifier) }
    }
}
