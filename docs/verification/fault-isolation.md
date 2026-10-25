# Build 32: source failure isolation and diagnostics

- 120 Swift tests passed, including injected quota timeout, malformed read JSON, missing history database, inventory expiry, identity timeout, closed helper, account mismatch and real socket failure.
- Live IPC subscriptions survive independent read failures. Disk recovery failure removes its baseline without removing live observations. Recovery resnapshots stay silent; failed history reads do not consume read invalidations.
- Quota/identity/read recovery retries are scheduled at five seconds. Inventory reads run every five seconds; old scope stops contributing counts after 30 seconds of failure. Identity errors hide all account data immediately; sustained failure (30 seconds), account change or closed helper forces fresh verification/reconnection.
- Unknown stream versions are ignored unless sent by the verified owner; only the affected stream is invalidated, with no fallback to stale disk results.
- Diagnostics use fixed stage/event labels and numeric error codes, no error descriptions, credentials, account/thread IDs or conversation content. Recovery reports include attempt count and duration. Files rotate at 1 MiB with one backup. Tests verify valid JSON after rotation and sensitive error-description exclusion.
- Universal Release build and ad-hoc signature verification passed. Packaged and launched `dist/Status Board.app` as build 32.
- Live check at 14:44 EDT: Connected, 1 processing, 0 waiting, 0 Done, root running, weekly quota 33%. Automatic `monitor_started` and `handshake/connected` records confirmed build 32 without diagnostic launch flags.
- Release package and live verification are recorded in `.build/idle-disconnection/`.

This addresses the demonstrated error-handling weakness. The original screenshot's precise transient failure was not captured by the previous build, so it is not claimed as an exactly reproduced incident.
