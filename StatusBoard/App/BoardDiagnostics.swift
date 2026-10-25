import Foundation
import StatusBoardDesktop

extension BoardDelegate {
    func writeSnapshotDiagnostics(_ snapshot: LiveSnapshot) {
        if let path = argument("--diagnostics") {
            // Explicit opt-in diagnostics contain aggregate state only, never IDs or content.
            let object: [String: Any] = ["time": snapshot.updatedAt.ISO8601Format(), "message": snapshot.message,
                "connected": snapshot.isConnected,
                "codexBuild": snapshot.codexBuild as Any? ?? NSNull(),
                "features": Dictionary(uniqueKeysWithValues: snapshot.features.map { ($0.key.rawValue, $0.value.state.rawValue) }),
                "audioEvents": snapshot.audioEvents.count, "audioPlaying": audio.isPlaying, "audioQueued": audio.pendingCount,
                "restoredDone": snapshot.restoredDone,
                "restoredCompleted": snapshot.restoredCompleted,
                "covered": snapshot.covered, "total": snapshot.total, "unassigned": snapshot.unassigned,
                "processing": snapshot.counts?.processing as Any? ?? NSNull(),
                "agentRows": snapshot.agents.count,
                "runningAgents": snapshot.agents.filter { $0.state == .running }.count,
                "doneAgents": snapshot.agents.filter { $0.state == .done }.count,
                "waiting": snapshot.counts?.waiting as Any? ?? NSNull(), "done": snapshot.counts?.done as Any? ?? NSNull(),
                "quota": snapshot.quota.map { ["label": $0.label, "remaining": $0.remaining] as [String: Any] }]
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
               let handle = FileHandle(forWritingAtPath: path) {
                do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])); try handle.close() } catch { try? handle.close() }
            }
        }
    }
}
