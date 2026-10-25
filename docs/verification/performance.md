# Performance qualification

Current baseline: **0.2.1 build 10**. V13 remains **NOT_RUN** for formal qualification. The integrated native panel and live adapter exist and can be measured; audio is implemented and can be measured; Focus integration remains deferred.

The observed roughly one-second completion update in the [initial preview](usable-preview.md) and recorded test durations are limited observations, not p95 latency or sustained resource measurements.

Remaining measurements on a Release build:

- 50 UI actions for p95 interaction latency.
- At least 20 real task/read transitions with documented source-to-widget timing.
- Quota freshness across a normal refresh interval, separating controlled fixtures from real-source evidence.
- Ten-minute idle CPU/memory baseline after warm-up, including owned helpers.
- Two-hour ordinary-use session with bursts, disconnect and wake; record crashes and memory drift.
- Formal event-to-audio latency and real burst/mute timing. Deterministic queue/cancellation checks are in [build 10](audio.md); Focus transition measurement awaits its implementation.

Use the targets and method in [V13](../status-board-implementation-plan-v0.1.md#v13--performance-and-stability). No formal performance or stability pass is claimed. See [current progress](results.md) for implementation status.
