# Multiple-conversation discovery and audio — build 31

October 24, 2026 (America/New_York). User reported that other conversations initially did not appear in Processing, then became visible later, and Waiting/Done were inaudible.

## Discovery correction

Build 30 prioritized recent inventory only at startup. New IDs were subsequently appended to the historical scan, activity in existing unloaded conversations did not promote them, and all eight requests could be occupied by unavailable historical owners for up to 15 seconds each. A short task could finish before subscription, producing only a silent recovery baseline.

Build 31 retains inventory activity timestamps and promotes new or recently updated conversations without a verified owner. It also consumes the inspected v1 `thread-stream-following-status-requested` announcement as a discovery hint. Unknown IDs trigger an inventory refresh; only current-account eligible IDs enter discovery, and only the discovered owner may supply accepted stream data. A known owner's announcement reestablishes its subscription. Remote hints and unverified versions do not bypass these checks.

Historical discovery uses at most six of the eight in-flight slots, leaving two for priority work. Promotion deduplicates IDs and preserves the unfinished historical tail. Historical inventory is not truncated, and a snapshot remains a silent baseline rather than generating catch-up sounds.

## Tests and real observations

**111 Swift tests pass.** Four added regression tests cover reserved slots and queue continuity, new/renewed activity during a background scan, hint scope/owner validation, and two simultaneous conversations with canonical-history Waiting/Done transitions delivered through AudioNotifications to playback. The prior native UI baseline remains 93 assertions; no view or interaction changes were made in build 31.

Read-only checks confirmed the three recently used other chats belong to the current account, are unarchived, and are not children. Independent IPC subscriptions found four owners and valid v11 snapshots. Their latest canonical turns remain compatible with the existing metadata projection. The packaged build 31 connected with four covered conversations out of 73 eligible conversations; startup included Processing 1 and Done 1. Other inventory is not claimed as live coverage.

The saved application mute preference is false. The packaged sound-preview mode started and finished completed, waiting and failed sounds successfully. Actual Waiting tests at 18:11:58Z and 18:12:35Z each recorded one live audio event with `audioPlaying: true`; Waiting became 1 and cleared on reply. The user initially reported not hearing the second Waiting sound. After a requested repeat of the three-tone preview, the user confirmed hearing all three. A further isolated real Waiting test was then confirmed audible by the user. No audio volume or playback implementation change was needed; the event-to-playback path and actual audibility were verified separately.

Read-only CoreAudio checks found the default output and system sound output both on MacBook Pro Speakers, unmuted, with scalar volume approximately 0.441. No system volume, output device or mute setting was changed.

Evidence: `.build/multi-conversation-validation/core-tests.log`, `package.log`, `ipc-before.jsonl`, `history-shape.jsonl`, `latest-shape.jsonl`, `audio-preview.log` and `live.jsonl`. Diagnostics contain aggregate state and field structure, not conversation text or credentials.

The final package is **0.2.1 build 31** (arm64/x86_64, ad-hoc signature verified). Temporary aggregate diagnostics were stopped and the same package restarted normally. Automatic Done delivery is covered by the two-conversation regression; its bundled tone was confirmed in the three-tone listening check. The final listening confirmation specifically exercised real Waiting, not a separate live completion.
