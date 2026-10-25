# Async question recognition — 0.2.1 build 11

## Reproduced issue

The user tested a real `request_user_input_async` question and heard no waiting sound; the screenshot showed processing 1 / Waiting for operation 0. This was a source-classification omission, not evidence that the playback driver failed.

Codex build 21477 stores async questions in `agentMessage.questions` and derives `unansweredAsyncQuestions` separately from blocking `requests` and runtime `activeFlags`. A read-only snapshot of the designated current conversation confirmed runtime active with no flags and no blocking requests, while the active turn contained one question and one accepted answer after the user's reply. The previous metadata projection omitted all turn items, so it could not see this question lifecycle.

## Fix

- Retain item IDs/types, question cardinality and accepted reply IDs for the latest covered in-progress turn, in both ordinary and canonical history.
- Extract reply IDs only from Codex's exact structured reply envelope. Question text, answer text, message bodies, options and tool payloads are discarded during projection and never retained or logged.
- Add unanswered async question IDs to the existing pending-input classification. Waiting takes precedence over active runtime and contributes one conversation, not one count per question.
- New live waiting entry uses the existing deduplicated serial waiting sound. Snapshots/reconnection stay silent. Partial replies leave the remaining questions pending; accepted replies clear only matching IDs. Completed turns do not retain stale waiting state.

## Validation

84 Swift tests pass (80 prior plus four async-question regressions). They cover active runtime with no waiting flags, real patch delivery into waiting, duplicate patches, reply clearing, canonical history, silent bootstrap, pending versus accepted steering replies, multiple/partial/wrong-ID replies, completed-turn cleanup, question-copy-only changes, malformed envelopes and a privacy sentinel proving text is not retained.

Evidence: `artifacts/app-validation/async-tests.txt`, `async-build.txt`, and the aggregate-only `async-live.jsonl`. The native retest passed as recorded below. Build 10's playback-driver evidence remains applicable; the sound assets and player are unchanged.

## Real retest result

The packaged build 11 was launched with temporary aggregate diagnostics. On the next question of the same async type, the user confirmed **Waiting for operation became 1 and the sound was audible**. Logs independently show processing 1 / waiting 0 -> processing 0 / waiting 1, exactly one audio event with active playback, then processing 1 / waiting 0 after the reply was accepted. No second waiting sound was emitted while the question remained pending or when the reply cleared it.

The saved mute preference was already off and was not changed. Temporary diagnostics were stopped after verification and the app was returned to normal launch. This passes the reported async-question scenario; Focus and the other broader audio/source acceptance cases remain pending.
