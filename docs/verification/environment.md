# Execution environment

Observed October 23, 2026 (America/New_York). User explicitly requested the currently installed, upgraded toolchain.

| Component | Observation |
| --- | --- |
| macOS | 15.8.1, build 24H32 |
| Xcode | 26.3, build 17C529 |
| Swift | Apple Swift 6.2.4, Swift 6 language mode |
| Selected developer directory | `/Applications/Xcode.app/Contents/Developer` |
| SDK | macOS 26.2 |
| Deployment target | macOS 15.0; only this host has been exercised |
| Execution architecture | x86_64 |
| Hardware | Intel Core i7-8850H CPU @ 2.60GHz, confirmed with an unrestricted read-only sysctl |
| Translation keys | `hw.optional.arm64` and `sysctl.proc_translated` absent; not interpreted as invented numeric values |
| Codex CLI | 0.163.0-alpha.11.2 |
| Third-party dependencies | None |
| Signing | Initial scaffold unsigned and native probe ad-hoc; current build 7 Release preview is locally ad-hoc signed with recorded strict signature verification; formal distribution/lifecycle qualification pending |

Verification ID: S00  
Execution mode: local compilation / native executable  
Actions: ran `scripts/verify-environment.sh`; compiled and executed a Foundation program using the selected SDK and Swift 6.  
Expected/observed: program compiles and prints `Foundation smoke PASS`.  
Status: PASS.  
Evidence: `artifacts/preflight/environment.txt`; source/build identities in `source-manifest.json`.

Initial restricted runs could not write tool caches or inspect the CPU brand. The preflight now uses a project-local module cache. SwiftPM tests use project-local cache/config/security directories. Xcode's package resolution required its normal user cache and succeeded with approved sandbox escalation. This was a tool permission issue, not a reason for another toolchain upgrade. No macOS/Xcode/Swift installation or upgrade was performed during this task.

Reproduce from the repository root:

```sh
scripts/verify-environment.sh
scripts/test-core.sh
scripts/build-probes.sh
scripts/build-app.sh Debug
```
