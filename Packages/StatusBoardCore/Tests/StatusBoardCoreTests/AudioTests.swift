import Foundation
import AppKit
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

@MainActor
private final class FakePlayback: AlertPlayback {
    var played: [AlertKind] = []
    var callbacks: [@MainActor () -> Void] = []
    var stops = 0
    var failNext = false
    func play(_ kind: AlertKind, completion: @escaping @MainActor () -> Void) -> Bool {
        played.append(kind)
        if failNext { failNext = false; return false }
        callbacks.append(completion); return true
    }
    func stop() { stops += 1 }
    func finish() { callbacks.removeFirst()() }
}

@MainActor
private final class AudioFixture {
    let player = FakePlayback()
    var now = Date(timeIntervalSince1970: 1_000)
    let generation = UUID()
    lazy var audio = AudioNotifications(playback: player, clock: { [unowned self] in self.now })
    func snapshot(_ kinds: [AlertKind], prefix: String = "event", thread: String = "T", account: String = "A") -> LiveSnapshot {
        var value = LiveSnapshot()
        value.accountFingerprint = account; value.audioGeneration = generation
        value.isConnected = true; value.updatedAt = now
        value.audioEvents = kinds.enumerated().map { i, kind in
            LiveAlert(thread: thread, transition: .init(occurrence: "\(prefix)-\(i)", kind: kind, revision: UInt64(i + 1)), observedAt: now)
        }
        return value
    }
}

@Test @MainActor func distinctEventsPlaySeriallyAndReplayIsConsumed() {
    let f = AudioFixture()
    let kinds: [AlertKind] = (0..<10).map { [.completed, .waiting, .failed][$0 % 3] }
    let snapshot = f.snapshot(kinds)
    f.audio.receive(snapshot)
    #expect(f.player.played == [.completed]); #expect(f.audio.pendingCount == 9)
    f.audio.receive(snapshot)
    #expect(f.audio.pendingCount == 9)
    for index in 1..<10 { f.player.finish(); #expect(f.player.played.count == index + 1) }
    f.player.finish()
    #expect(f.player.played == kinds); #expect(!f.audio.isPlaying)
}

@Test @MainActor func muteCancelsActiveAndQueuedAudioAndNeverCatchesUp() {
    let f = AudioFixture()
    f.audio.receive(f.snapshot([.completed, .waiting]))
    f.audio.setMuted(true)
    #expect(!f.audio.isPlaying); #expect(f.audio.pendingCount == 0)
    f.now += 1
    let muted = f.snapshot([.failed], prefix: "muted")
    f.audio.receive(muted)
    f.audio.setMuted(false)
    f.player.finish() // Late completion from the cancelled player.
    f.audio.receive(muted)
    #expect(f.player.played == [.completed])
    f.now += 1
    f.audio.receive(f.snapshot([.waiting], prefix: "new"))
    #expect(f.player.played == [.completed, .waiting])
}

@Test @MainActor func preMuteEventsDeliveredAfterUnmuteAreDiscarded() {
    let f = AudioFixture()
    let delayed = f.snapshot([.completed])
    f.now += 1; f.audio.setMuted(true)
    f.now += 1; f.audio.setMuted(false)
    f.audio.receive(delayed)
    #expect(f.player.played.isEmpty)
}

@Test @MainActor func disconnectGenerationAccountAndHealthCancelQueues() {
    let f = AudioFixture()
    f.audio.receive(f.snapshot([.completed, .waiting]))
    var disconnected = f.snapshot([]); disconnected.isConnected = false
    f.audio.receive(disconnected)
    #expect(f.audio.pendingCount == 0); #expect(!f.audio.isPlaying)
    f.player.finish()
    f.now += 1
    var reconnected = f.snapshot([.completed]) // Duplicate occurrence after reconnect.
    reconnected.audioGeneration = UUID()
    f.audio.receive(reconnected)
    #expect(f.player.played == [.completed])
    f.audio.receive(f.snapshot([.failed, .waiting], prefix: "other", account: "B"))
    #expect(f.audio.pendingCount == 1)
    f.now += 11; f.audio.checkHealth()
    #expect(!f.audio.isPlaying); #expect(f.audio.pendingCount == 0)
    f.player.finish()
    #expect(f.player.played == [.completed, .failed])
}

@Test @MainActor func perThreadDiscontinuityCancelsOnlyAffectedEvents() {
    let f = AudioFixture()
    f.audio.receive(f.snapshot([.completed, .waiting], prefix: "one", thread: "T1"))
    f.audio.receive(f.snapshot([.failed], prefix: "two", thread: "T2"))
    var invalidated = f.snapshot([]); invalidated.invalidatedAudioThreads = ["T1"]
    f.audio.receive(invalidated)
    #expect(f.player.played == [.completed, .failed]); #expect(f.audio.pendingCount == 0)
    f.player.finish() // Old T1 completion cannot advance/stop T2.
    #expect(f.audio.isPlaying)
    f.player.finish(); #expect(!f.audio.isPlaying)
}

@Test @MainActor func playbackFailureIsConsumedAndLaterSoundsContinue() {
    let f = AudioFixture(); f.player.failNext = true
    f.audio.receive(f.snapshot([.completed, .waiting]))
    #expect(f.player.played == [.completed, .waiting]); #expect(f.audio.pendingCount == 0)
    f.player.finish()
    f.audio.receive(f.snapshot([.completed, .waiting]))
    #expect(f.player.played.count == 2)
}

@Test @MainActor func sleepWakeAndShutdownNeverReplayOldEvents() {
    let f = AudioFixture()
    f.audio.receive(f.snapshot([.waiting, .failed]))
    f.audio.setSuspended(true)
    f.now += 1
    let duringSleep = f.snapshot([.completed], prefix: "sleep")
    f.audio.receive(duringSleep)
    f.now += 1; f.audio.setSuspended(false)
    f.audio.receive(duringSleep)
    #expect(f.player.played == [.waiting]); #expect(f.audio.pendingCount == 0)
    f.now += 1; f.audio.receive(f.snapshot([.failed], prefix: "wake"))
    #expect(f.player.played == [.waiting, .failed])
    f.audio.shutdown(); f.player.finish(); f.player.finish()
    f.audio.receive(f.snapshot([.completed], prefix: "quit"))
    #expect(!f.audio.isPlaying); #expect(f.player.played.count == 2)
}

@Test @MainActor func bundledSoundsDecodeAsDistinctShortAssetsWithoutPlaying() throws {
    var assets = Set<Data>()
    for kind in [AlertKind.completed, .waiting, .failed] {
        let url = try #require(BundledAlertPlayback.assetURL(for: kind))
        assets.insert(try Data(contentsOf: url))
        let sound = try #require(NSSound(contentsOf: url, byReference: false))
        #expect(sound.duration >= 0.3 && sound.duration <= 0.8)
    }
    #expect(assets.count == 3)
}

@Test @MainActor func expiredQueuedSoundsAreSkippedAndNeverReplay() {
    let f = AudioFixture()
    let burst = f.snapshot(Array(repeating: .completed, count: 30))
    f.audio.receive(burst)
    // Keep the connection healthy while each short sound finishes normally.
    for _ in 1...17 {
        f.now += 0.6
        f.audio.receive(f.snapshot([]))
        f.player.finish()
    }
    #expect(f.player.played.count == 17)
    #expect(f.audio.pendingCount == 0 && !f.audio.isPlaying)
    f.audio.receive(burst)
    #expect(f.player.played.count == 17)
    f.audio.receive(f.snapshot([.waiting], prefix: "fresh"))
    #expect(f.player.played.last == .waiting)
    #expect(f.player.played.count == 18)
}

@Test @MainActor func queuedSoundAtAgeLimitStillPlays() {
    let f = AudioFixture()
    f.audio.receive(f.snapshot([.completed, .waiting]))
    f.now += 10
    f.audio.receive(f.snapshot([]))
    f.player.finish()
    #expect(f.player.played == [.completed, .waiting])
}
