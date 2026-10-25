# Live audio notifications — 0.2.1 build 10

The user requested implementing notification sounds after the earlier audio deferral. Build 10 adds audio to the existing build 9 monitoring implementation. **Focus integration remains deferred. Direct NSSound playback does not automatically honor macOS Focus**; the current preview uses the saved Mute Sounds preference. This is not a pass for the original Focus requirement.

## Behavior

- Three original bundled PCM WAV assets: completion (rising pair, 0.58 s), waiting (repeated notes, 0.52 s), stopped error (lower descending pair, 0.56 s). They follow system output volume and can be regenerated with `scripts/generate-alert-sounds.py`.
- Verified contiguous live stream patches produce transient events separately from aggregate counts. Snapshots, disk completion/unread recovery, read-state changes and quota updates do not produce sounds. Event delivery is immediate rather than waiting for the one-second aggregate refresh.
- A new completion can sound even when already read. Intentional interruption, active automatic retry and unverified heartbeat alerts remain silent.
- Runtime waiting flags and request arrival share a single waiting-entry event. A return to running followed by another wait can produce a new event. A failed status that arrives before the task stops does not alert until the stopped state arrives.
- A main-actor queue plays one event at a time. Stable occurrence IDs deduplicate replay, including suppression; failed starts are consumed without retry, and a watchdog prevents a lost playback callback from blocking the queue.
- Mute immediately cancels queued and active sounds. Events received while muted, and older callbacks delivered after unmuting, cannot become catch-up sounds. Existing saved mute preference is preserved.
- Disconnect, account/session replacement, expired monitor updates, sleep and quit cancel audio. Per-thread source gaps, owner replacement and removal cancel affected thread audio. Wake restarts the monitor with a silent baseline. The player never changes window focus, expansion or pin state.

## Verification

Execution: deterministic tests plus a native packaged-driver smoke check. No Codex prompts, approvals, read flags or conversation modifications were used for these tests.

**80 Swift tests pass** (67 existing plus 13 audio-related additions). New coverage includes ten serial mixed events; replay deduplication; cancellation and late callbacks; mute/unmute without catch-up; account/generation/disconnect/expiry handling; per-thread invalidation; playback start failure; sleep/wake/quit; distinct short resource decoding; split wait signals; failed-status-before-stop; and real session coordinator delivery/readiness/gap recovery using temporary stores and a fake transport. The regular test suite does not play audio.

The packaged application's explicit `--preview-sounds` mode runs the actual bundled NSSound driver without starting monitoring or changing preferences. All three sounds started successfully and completed before the watchdog: completion 1.019 s, waiting 0.623 s, failure 0.668 s from play call to callback. These timings include driver startup and are not an event-to-audio latency qualification or a subjective listening assessment. This opt-in mode intentionally ignores the normal panel's mute preference; ordinary launches do not.

Release packaging succeeded for x86_64 and arm64 and strict ad-hoc signature verification passed. A 20-second Launch Services startup run recorded 20 aggregate samples (19 connected), four live conversations and 55 recovered completed conversations at the last sample. All samples had zero audio events, no active playback and an empty queue: startup/recovered history remained silent. This is baseline evidence, not an induced real completion/approval/error test.

Evidence paths:

- `artifacts/app-validation/audio-tests.txt`
- `artifacts/app-validation/audio-build.txt`
- `artifacts/app-validation/audio-preview.txt`
- `artifacts/app-validation/audio-live.jsonl` (aggregate-only startup check)

## Limits and remaining acceptance

Audio can only represent live events actually supplied by the verified local source. Whole-source active/waiting coverage and real approval/error/retry sequences remain to be qualified; an unloaded historical conversation alone does not prove a missing active desktop task. Interrupted streams rebaseline silently, so uncertain/missed events are not reconstructed into sounds. Cross-conversation ordering follows observer arrival order, not an unavailable global server clock.

Full real-source listening/volume/device-failure, manual mute, sleep/wake and long-burst checks remain pending. Focus permission/state detection and its suppression matrix remain unimplemented. V11 is IN_PROGRESS, not a complete original-specification pass.
