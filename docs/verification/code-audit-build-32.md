# Build 32 代码审查（2026-10-24）

后续状态：本文记录 build 32 的审查现场；四项问题及清理工作已在 build 33 处理，见 [build 33 验证](review-fixes-build-33.md)。

范围：正式 Swift Core/Desktop 模块、App 状态与窗口逻辑、构建与测试入口、相关历史探针的引用关系。本次是审查，未修改正式源码、重启应用或删除历史实验。

验证：在现有测试套件中临时加入四个独立边界场景，运行 124 项测试。原有 120 项通过；新增 4 项均复现问题，共 7 条断言失败。临时测试已从正式测试目录移出，复现场景保留在 `.build/code-audit/ReviewAuditTests.swift`，输出在 `.build/code-audit/test-results.log`。所有场景使用临时目录、合成数据和模拟时钟/传输，不连接真实账号。

## 已确认的问题

1. **P1：慢读取之后，已经到达的大快照仍会被误判超时。**
   - 位置：`DesktopSession.swift:73–80`、`DesktopSocket.swift:62–65`、`DesktopSession.swift:258–260`。
   - 会话循环先同步读取身份/磁盘，再只接收一次最多 64 KiB 的 socket 数据，紧接着检查超时。大快照虽然已在 socket 缓冲区，第一段却不能组成完整消息，因此不会解除快照期限。
   - 复现：90 KB 快照分为两段；先模拟额度读取消耗 5.1 秒，再执行循环。第一段读完就删除 owner；第二段完整快照因 owner 已消失而被忽略。结果是正常处理中的任务从计数消失。
   - 建议：对已经可读的数据采用有界 drain；在判断期限时考虑仍在接收的帧。更彻底的改法是让慢 RPC 读取与 IPC 接收分离，但要保持账号和会话世代校验，不能简单无限放宽期限。

2. **P2：异常额度结构被当成成功，覆盖旧额度并清除错误状态。**
   - 位置：`DesktopSession.swift:230–238`。
   - `as?` 和 `compactMap` 会把结构错误或无效窗口静默变成空数组，随后仍更新 `quotaDate`。调用方将其标记为恢复，并等 60 秒再读；不会留下此次格式异常的失败日志。
   - 复现：先成功读取剩余 60%，再返回正确 accountId、但 rateLimits 为字符串的响应。额度变空，失败状态仍为空。
   - 建议：区分合法无额度/无该桶与字段结构异常；完整验证后再一次性替换额度和成功时间，异常保留旧值并按失败路径记录重试。

3. **P2：已验证账号、握手成功但尚未取得额度时，保存的额度被空数组遮蔽。**
   - 位置：`DashboardPresentation.swift:50–51`，与 build 32 的连接状态不再依赖 quotaDate 的改动相互影响。
   - `visibleSnapshot()?.quota` 返回的是非 nil 的空数组，`??` 不会回退到已验证账号的保存额度。启动或重连后，如果首次额度请求持续失败，明明有保存值也会一直显示空白额度。
   - 复现：先保存 60%，然后收到相同账号的已连接快照但 quotaDate 为 nil、quota 为空。windows() 返回空数组。
   - 建议：单独表达“尚未成功读取额度”与“成功读取到空结果”，只在前一种状态使用匹配账号的缓存，并明确缓存的新鲜度。

4. **P2：会话确认卸载后，旧的 streamIssues 不会清理。**
   - 位置：`DesktopSession.swift:304`、`DesktopSession.swift:240–245`。
   - 协议异常会加入 streamIssues，但随后 owner discovery 返回 no-client-found 时，只移除订阅。会话仍在 inventory 内，所以 inventory 的集合裁剪也不能移除该标记。
   - 复现：收到版本 12 的会话快照后，再返回 no-client-found，提示仍然是 Connected · retrying conversation data。
   - 建议：在确认卸载或不再跟踪时清理相应告警；区分暂时不可达、等待重同步、已确认卸载三种状态，并记录告警结束原因。

## 复杂度与测试维护

- `DesktopSession.swift` 403 行，同时管理 RPC、IPC、身份、发现队列、五类数据读取、恢复、声音和视图投影。问题主要是职责和生命周期状态分散，而不是大量深层 if。尤其是 `handle` 同时处理握手、发现响应、广播、流补丁和告警，适合先拆成具名处理函数，再把“移除会话”统一成带原因的状态转移。
- `readInventory()`（115 行）与 `readRecovery()`（137 行）已不被正式运行循环调用，但大量旧测试仍调用它们。正式循环走 refreshInventory()/refreshRecovery()，后者另外维护错误状态、重试时间、缓存失效。应统一入口；否则两个路径容易继续分叉。
- `BoardDelegate` 位于 553 行的应用入口文件中，同时承担窗口恢复、菜单、设置、声音、持久化和可选诊断。可以按窗口控制、设置和诊断输出分拆，保持现有交互行为。拆文件本身不能替代状态收敛。
- `MetadataJSONParser` 和 `ProcessingAgents.appendChildren` 的嵌套主要源于 JSON/代理树结构；前者有 128 层限制，后者有 visited 去重。没有足够证据将这些递归本身判断为缺陷，不建议为缩短代码换成全量 JSON 缓冲。

## 旧代码与实验残留

- `DesktopFrameDecoder`（`DesktopStream.swift:43`）已经不服务正式应用，正式 IPC 用 DesktopMetadataDecoder。它仍由旧 DesktopIPCProbe 和对应测试调用，因此属于放在核心模块里的历史探针实现，并非无人引用。建议迁入探针支持目录或统一探针解码器。
- `Probes/DesktopLensCheck`、`Probes/GlassBackdrop` 和 Liquid-TUI 说明属于已退出正式产品的玻璃实验。没有进入 StatusBoard 主 target；DesktopLensCheck 仍有独立脚本，GlassBackdrop 在历史验证文档中有记录。可集中归档，但保留实验时必须保留相应许可证。
- Swift/Python DesktopIPCProbe 仍只允许 build 21477，而正式应用支持 21828。直接拿旧探针排查当前版本会报 unsupportedBuild；应明确标记为历史工具或同步其兼容范围。
- `Probes/DesktopIPCProbe/__pycache__/probe.cpython-314.pyc` 是 Python 生成缓存，`.gitignore` 未覆盖 `__pycache__/`、`*.pyc`。
- `.build` 约 1 GB、artifacts 约 135 MB，属于构建与验证产物，不能据此认定为废弃源码；未做清理。

建议顺序：先修正第 1 项接收/超时问题，再修正额度状态语义及告警生命周期，随后统一测试入口，最后整理历史探针和应用类职责。
