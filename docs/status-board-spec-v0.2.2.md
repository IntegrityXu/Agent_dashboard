# Status Board 规格说明（SPEC）

| 项目 | 内容 |
| --- | --- |
| 文档版本 | 0.1（草案，待上游评审） |
| 上游需求 | [`docs/status-board-prd-v0.2.2.md`](status-board-prd-v0.2.2.md) 文档版本 1.0（commit `3a3950f`） |
| 产品基线 | Status Board 0.2.2 build 39 个人预览版 |
| 编写日期 | 2026-10-27 |
| 用途 | 把 PRD 的产品语义收敛为可直接实现、可直接写测试的规则：数据模型、判定函数、状态机、参数表、不变量和追溯矩阵 |
| 技术约束 | 与 PRD 一致，不限定语言、框架、存储或通信实现；文中伪代码只表达语义 |

## 0 阅读约定

### 0.1 与 PRD 的关系

- PRD 定义“产品应当表现成什么样”；本 SPEC 定义“按什么规则算出来”。两者冲突时**以 PRD 为准**，并在第 22 节登记为待澄清项。
- PRD 没写、但实现等价重写必须作出选择的地方，本 SPEC 采用当前实现（build 39）的行为作为默认值，标注 **〔据实现〕**，并同时列入第 22 节请上游确认是否属于产品承诺。
- 本 SPEC 不新增功能，不修改 PRD 第 2.2 节的排除范围。

### 0.2 规范用语

| 用语 | 含义 |
| --- | --- |
| **MUST / 必须** | 违反即视为缺陷，对应 PRD 中的“应”“必须” |
| **MUST NOT / 禁止** | 同上，反向约束 |
| **SHOULD / 宜** | 默认要求；偏离须在实现说明中写明理由 |
| **MAY / 可** | 允许但不要求 |

### 0.3 编号体系

| 前缀 | 含义 |
| --- | --- |
| `F01`–`F16` | PRD 功能编号（沿用） |
| `A01`–`A54` | PRD 验收用例编号（沿用） |
| `INV-nn` | 系统不变量，任何时刻都必须成立 |
| `R-<域>-nn` | 本 SPEC 的规则条目，可单独写测试 |
| `K-<名称>` | 具名参数常量（第 15 节） |
| `Q-nn` | 待上游澄清的问题（第 22 节） |
| `AX-nn` | 本 SPEC 建议补充的验收用例（第 21.2 节） |

## 1 系统分解

### 1.1 逻辑组件

实现可以任意合并或拆分进程、模块，但必须能在测试中独立替换下列**来源适配器**，以便注入故障（A49）。

```
              ┌──────────── 来源适配器（只读）────────────┐
 Codex 桌面端 │ IdentitySource   InventorySource          │
  及其本地数据 │ LiveStreamSource ReadStateSource          │
              │ HistorySource    QuotaSource  AgentSource │
              └───────────────┬──────────────────────────┘
                              │ 归一化观察（第 2 节类型）
              ┌───────────────▼──────────────────────────┐
              │ 核心（纯函数 + 小状态机，时钟可注入）      │
              │ ScopeFilter → Classifier → Aggregator     │
              │ UnreadRecovery  SideChatRegistry          │
              │ AgentProjection CompactTracker AvatarClock│
              │ AlertPipeline   FeatureStatus/Presentation│
              └───────────────┬──────────────────────────┘
                              │ PresentationSnapshot（约 1 秒一次）
              ┌───────────────▼──────────────────────────┐
              │ 外壳：Window / MenuBar / Settings /        │
              │ AudioOutput / Preferences / Diagnostics    │
              └───────────────────────────────────────────┘
```

| 组件 | 职责 | PRD |
| --- | --- | --- |
| IdentitySource | 发现 Codex、产出已验证身份或失败原因 | 5.1、14.2 |
| InventorySource | 本地会话清单：身份、本地性、归属、归档、子 Agent、侧聊标记 | 3.1 |
| LiveStreamSource | 会话实时观察，带连接代次与连续性信息 | 6、14 |
| ReadStateSource | Codex 已读集合（当前用户 + 本机） | 7 |
| HistorySource | 最新轮次完成证据 | 7.1 |
| QuotaSource | 额度窗口 | 9 |
| AgentSource | 主任务的 Agent 活动 | 8.2 |
| Classifier | 第 5 节判定函数 | 6.1 |
| Aggregator | 去重、计数、`—`/0 判定 | 3.2 |
| AlertPipeline | 事件去重、队列、新鲜度、取消 | 11 |
| CompactTracker | 紧凑角标事件先后 | 10.1 |
| AvatarClock | 休眠计时 | 10.2 |

### 1.2 核心约束

- **R-ARCH-01** 核心组件 MUST 以可注入时钟运行；所有时间判断（10 秒新鲜度、30 分钟休眠、宽限期）MUST 可在测试中确定性复现。
- **R-ARCH-02** 来源适配器 MUST NOT 向 Codex 写入任何数据（不提交提示、不批准、不标记已读、不修改会话）。
- **R-ARCH-03** 每个来源的结果 MUST 携带 `(identityGeneration, connectionGeneration, requestSeq)`；核心 MUST 丢弃任何代次低于当前代次的迟到结果（PRD 14.3 末段）。
- **R-ARCH-04** 一个来源的失败 MUST 只改变它自己的 FeatureStatus 和它贡献的数据，MUST NOT 让其他来源已验证的数据失效（PRD 14.2）。例外见 R-AVAIL-04。

## 2 数据模型

以下用类 TypeScript 记法表达语义字段，不规定序列化格式。`?` 表示可缺失；缺失与“值为空”含义不同，MUST 区分。

```ts
type Instant = number            // 单调或墙钟时间，见 R-TIME-01
type Generation = number         // 单调递增，切换时 +1

interface VerifiedIdentity {
  service: string                // 服务来源
  account: string                // 账户
  userScope: string              // 同组织下的用户范围
  fingerprint: string            // hash(service, account, userScope)，用作缓存键
  generation: Generation         // 身份代次；身份变化或失效后重建时 +1
}

interface ConversationScope {
  id: string                     // 会话身份（去重键）
  isLocal: boolean
  accountMatches: boolean | "unknown"
  archived: boolean
  isSubAgent: boolean
  isSideChat: boolean
  parentId?: string              // 侧聊派生来源
}

type Runtime = "active" | "systemError" | "idle" | "notLoaded" | string   // 未知值保留原文
type TurnStatus = "inProgress" | "completed" | "failed" | "interrupted" | string

interface LiveObservation {
  conversationId: string
  runId?: string                 // 当前执行轮次身份
  runtime?: Runtime
  turnStatus?: TurnStatus        // 缺失 = 当前没有轮次状态
  pendingRequestIds: Set<string> // 已识别的待回答/待批准请求
  hasUnclassifiedRequests: boolean
  unansweredQuestionIds: Set<string>
  unread?: boolean               // 缺失 = 未读状态未确认
  hasLatestTurnCoverage: boolean // 已确认观察覆盖到最新轮次
  isHeartbeat: boolean           // 轮次由 heartbeat 自动化发起，见 Q-03
  observedAt: Instant
  connectionGeneration: Generation
  continuity: "ok" | "gap"       // 版本缺口或已知流中断 = gap
}

type TaskState =
  | "processing" | "waitingUser" | "waitingError"
  | "completed" | "stopped" | "idle" | "unknown"

interface QuotaWindow {
  key: string                    // 周期身份，非空，同一组内唯一
  durationMinutes?: number
  sourceLabel?: string           // 来源给出的权威名称，见 R-QUOTA-03
  usedPercent: number            // 有限值，[0, 100]
  resetAt?: Instant
}

interface SavedUsage {
  fingerprint: string
  windows: QuotaWindow[]
  quotaReadAt: Instant
  lastCompleteSyncAt?: Instant
}

type FeatureName = "Live tasks" | "Usage" | "History recovery" | "Agent list"
type FeatureState = "available" | "checking" | "partial" | "unavailable" | "incompatible" | "saved"

interface AlertEvent {
  kind: "completed" | "waiting" | "failed"
  conversationId: string
  runId: string
  occurrence: string             // 去重键，见 R-ALERT-02
  observedAt: Instant
  connectionGeneration: Generation
  identityGeneration: Generation
}

interface Preferences {          // 唯一持久化的用户状态（另加 SavedUsage）
  origin: { x: number; y: number }
  displayId: string
  expanded: boolean
  detailsVisible: boolean        // 默认 true
  pinned: boolean                // 默认 false
  muted: boolean                 // 默认 false
}
```

- **R-DATA-01** 原始认证材料 MUST 只存在于内存，MUST NOT 进入 `SavedUsage`、`Preferences` 或日志。
- **R-DATA-02** 任何会话正文、工具参数、命令、问答正文、错误原文 MUST NOT 出现在上述任何持久化类型或普通日志中（PRD 16.2）。
- **R-DATA-03** `LiveObservation`、`AlertEvent`、计数、角标、Agent 活动、休眠计时 MUST NOT 持久化（PRD 9.3、15）。

## 3 不变量

| 编号 | 不变量 | 违反示例 | 相关验收 |
| --- | --- | --- | --- |
| INV-01 | 每个会话 ID 至多贡献 1 个计数，且至多属于 Processing / Waiting / Done 之一 | 两个窗口导致 Processing 2 | A02、A05 |
| INV-02 | 子 Agent 永远不贡献顶层计数，也不触发顶层提示音 | 子 Agent 完成导致 Done +1 | A15、A20 |
| INV-03 | 屏幕上所有与账户相关的值（计数、额度、Saved、角标）都来自当前已验证身份；身份未验证时这些值全部不可见 | 启动瞬间闪现旧账户额度 | A01、A17 |
| INV-04 | `0` 只在有正面证据时出现；证据不足显示 `—` | 清单非空、无观察时显示 0 | A16 |
| INV-05 | 同一 `occurrence` 在一个身份代次内至多播放一次 | 重连后重复完成音 | A27、A33 |
| INV-06 | 启动、重连、恢复、已读变化、额度变化永不产生提示音 | 启动补播历史 | A11、A30 |
| INV-07 | 可见任务数据的年龄 ≤ `K-SNAPSHOT-MAX-AGE`（10 秒） | 断线后旧 Processing 一直显示 | A50 |
| INV-08 | 产品对 Codex 零写入 | 点击 Done 把会话标记为已读 | A12、A43 |
| INV-09 | 后台更新不改变窗口形态、位置、置顶偏好，也不抢夺键盘焦点 | 新完成事件把面板展开 | A39、A40 |
| INV-10 | 迟到结果（旧身份、旧连接代次、旧请求序号、旧轮次）不覆盖新状态 | 旧已读响应把 Done 恢复回 1 | A13、A14 |

## 4 会话纳入范围（F02、PRD 3.1）

### 4.1 主会话谓词

```
inScope(c) :=
     identity is verified
  && c.isLocal
  && c.accountMatches == true
  && !c.archived
  && !c.isSubAgent
  && !c.isSideChat                 // 侧聊走第 8 节
```

- **R-SCOPE-01** `accountMatches == "unknown"` 的会话 MUST 计入 Info 的“无法验证归属的遗留会话”数量（`unassigned`），MUST NOT 进入任何计数。
- **R-SCOPE-02** 发起入口（桌面、CLI 等）MUST NOT 作为排除条件；它只影响能否取得实时观察。
- **R-SCOPE-03** 范围总数 `total = |inScope 主会话| + |已接纳侧聊|`。
- **R-SCOPE-04** 清单读取失败时，可沿用上一次成功的范围，最长 `K-INVENTORY-GRACE`（30 秒）；超过后或遇到格式不兼容（立即），任务统计、Agent 行和角标 MUST 隐藏，受影响提示音 MUST 取消（PRD 14.2 末行）。

### 4.2 去重

- **R-SCOPE-05** 去重键为会话 ID。同一会话的多份观察（多窗口）MUST 合并为一份，以 `(connectionGeneration, observedAt)` 最新者为准。

## 5 状态判定（F02、F03、PRD 6.1）

### 5.1 判定函数

对每个已纳入且观察有效（R-CLASS-02）的会话，按顺序求值，命中即返回：

```
classify(o: LiveObservation): TaskState
  1  if |o.pendingRequestIds| > 0 or |o.unansweredQuestionIds| > 0  → waitingUser
  2  if o.hasUnclassifiedRequests                                   → unknown
  3  if o.runtime == "active"                                       → processing
  4  if o.runtime == "systemError"                                  → waitingError
  5  if o.turnStatus == "inProgress"                                → processing
  6  if o.turnStatus == "failed"                                    → waitingError
  7  if o.turnStatus == "interrupted"                               → stopped
  8  if o.turnStatus == "completed"
        → (o.unread 缺失) ? unknown : completed
  9  if o.turnStatus 缺失 and o.runtime == "idle" and o.hasLatestTurnCoverage → idle
  10 otherwise                                                      → unknown
```

计数映射：

| TaskState | 计入 | 是否算“已确认实时覆盖”（`covered`） |
| --- | --- | --- |
| processing | Processing | 是 |
| waitingUser、waitingError | Waiting | 是 |
| completed 且 `unread == true` | Done | 是 |
| completed 且 `unread == false` | 不计 | 是 |
| idle、stopped | 不计 | 是 |
| unknown | 不计 | **否** |

- **R-CLASS-01** 步骤 1 中待处理事项无论多少个，Waiting 只 +1（INV-01）。
- **R-CLASS-02** 观察有效性先于判定：`continuity == "gap"`、身份不匹配、关键字段无法解析的观察 MUST 被视为“无观察”，不进入 `classify`，并触发该会话重新同步（PRD 14.2 “单会话数据不连续”行）。
- **R-CLASS-03** 未知的 `runtime` / `turnStatus` 字符串 MUST 归为 unknown，MUST NOT 映射到最接近的已知值。
- **R-CLASS-04** 来自持久历史的 `inProgress` MUST NOT 产生 processing；processing 只能来自当前连接代次内的实时观察。
- **R-CLASS-05** `waitingError` 的离开条件只有：新轮次开始、会话离开范围、或观察失效。Codex 已读变化 MUST NOT 清除 waitingError。〔据实现〕见 Q-04。

### 5.2 异步问题（PRD 6.4）

- **R-ASK-01** `unansweredQuestionIds` 只包含属于 `o.runId` 的问题；轮次改变时集合 MUST 清空。
- **R-ASK-02** 问题 `q` 只能被“问题身份等于 `q` 且被来源标记为已接受”的回答移出集合。修改问题文案、未接受回复、身份不匹配 MUST NOT 移出。
- **R-ASK-03** 问题正文、选项、回答 MUST NOT 被保存或展示。

## 6 聚合与 `—`/0 判定（PRD 3.2）

```
counts = Σ classify(o) over 有效观察 ∪ 已接纳侧聊观察
counts.done += restoredDone             // 第 7 节，已与实时去重
covered = |有效观察中 classify ≠ unknown|

showCounts :=
     identity verified
  && taskFeature 未处于 R-SCOPE-04 的隐藏状态
  && ( covered > 0 || restoredCompleted > 0 || restoredDone > 0 || total == 0 )

display = showCounts ? counts : "—"（三项同时）
```

- **R-AGG-01** `total == 0` 且身份已验证、清单成功时 MUST 显示 `0 / 0 / 0`。〔据实现〕PRD 原文为“可以”，见 Q-05。
- **R-AGG-02** `restoredCompleted > 0`（已确认有完成历史，但全部已读）时 Done MUST 可以为 0，即使 `covered == 0`（PRD 3.2 第 6 条）。
- **R-AGG-03** `—` 是三项一起出现的；本 SPEC 不定义“Processing 有值、Done 为 `—`”的混合态。〔据实现〕
- **R-AGG-04** `partial := covered < total || unassigned > 0`。`partial` 为真时数字照常显示，Info MUST 披露 `covered/total` 与 `unassigned`。

## 7 完成未读恢复（F04、PRD 7）

### 7.1 恢复集合

```
restoredDone(c) :=
     inScope(c)                                // 主会话；侧聊不参与
  && history.latestTurn(c).status == "completed"
  && history.latestTurn(c).completedAt 存在
  && c ∈ readState.unreadSet(当前账户, 当前用户, 本机)
  && c 没有有效实时观察                         // 实时优先，避免重复
  && c 未被标记为 "historyFallbackBlocked"      // 见 R-REC-03
```

`restoredCompleted(c)` 同上但去掉 unread 条件，用于 R-AGG-02。

- **R-REC-01** `failed`、`interrupted`、`inProgress` 的历史轮次 MUST NOT 产生 restoredDone。
- **R-REC-02** 一旦会话出现有效实时观察，它 MUST 只由实时观察计数，恢复贡献立刻移除。
- **R-REC-03** 当会话出现以下任一情况，标记 `historyFallbackBlocked`，直到观察到新的完整最新轮次：实时进入了新轮次；已知实时流中断/版本缺口；最新历史不完整（A13、A14）。
- **R-REC-04** 恢复过程 MUST 静音（INV-06），也 MUST NOT 写入 CompactTracker 的事件先后（角标走 baseline）。

### 7.2 已读核对

已读变化可能不改变运行状态版本，因此需要独立核对。

- **R-READ-01** 已读核对请求携带单调 `requestSeq`；只有 `requestSeq` 大于最后已应用序号的结果才能应用（INV-10）。
- **R-READ-02** 核对进行中若检测到新的变更信号，MUST 在当前请求结束后再发起一次，MUST NOT 并发发起重复请求。
- **R-READ-03** 实时 Done 的补偿核对节奏：首次 `K-READ-FIRST`（1 秒），之后 `K-READ-INTERVAL`（5 秒）；历史复核节奏 `K-HISTORY-INTERVAL`（5 秒），检测到变更后 `K-HISTORY-DEBOUNCE`（250 毫秒）合并刷新。
- **R-READ-04** 组件内任何操作（点击 Done、打开 Info、展开/收起）MUST NOT 改变已读状态（INV-08）。

## 8 临时侧聊（F05、PRD 8.1）

### 8.1 接纳谓词

```
acceptSideChat(s) :=
     s.isLocal && identity verified for s
  && s.isSideChat && !s.isSubAgent
  && ancestorChain(s) 最终指向某个 inScope 主会话
  && 验证在 K-SIDECHAT-VERIFY-TIMEOUT（30 秒）内完成
```

- **R-SIDE-01** 收到未知会话的广播 MUST NOT 视为接纳；未接纳前不计数、不发声。
- **R-SIDE-02** 待验证 + 已接纳合计上限 `K-SIDECHAT-CAP`（64）。超出时新候选 MUST 不被接纳，且 Info 的 Live tasks 状态 SHOULD 体现部分覆盖。见 Q-08。

### 8.2 生命周期状态机

```
 (广播) ──► Candidate ──验证通过──► Accepted ──► Observed
               │ 超时/失败              │
               ▼                        ├─ 最后窗口离开且非活动 ──(K-SIDECHAT-RELEASE ≈2s)──► Released
            Dropped                     ├─ 祖先离开范围 ──► Removed（级联移除依赖它的侧聊）
                                        ├─ 转为持久主会话 ──► 移交主会话范围（保留已验证状态，不重复计数）
                                        └─ 连接代次变化 ──► 全部丢弃，从新连接重新发现
```

- **R-SIDE-03** 窗口隐藏但侧聊仍 processing / waiting 时 MUST 保持 Observed。
- **R-SIDE-04** 接纳后的首个观察只建立基线，不产生提示音和角标事件。

## 9 Agent 活动（F06、PRD 8.2）

- **R-AGENT-01** 只为 `classify == processing` 且 `turnStatus ∉ {completed, failed, interrupted}` 的主任务投影活动行：一个 `root` 加已验证子 Agent。已接纳侧聊也视为主任务，会有自己的 `root` 行〔据实现，见 Q-07〕。子 Agent 行只在主任务 `hasLatestTurnCoverage` 时展开。
- **R-AGENT-02** 活动列表以 `(conversationId, runId)` 为键；`runId` 变化或任务离开 processing 时 MUST 立即丢弃旧列表。
- **R-AGENT-03** 显示名取路径末段；过长时中间截断，状态后缀 MUST 完整可见。后缀映射：`running → "....."`、`done → " done"`、`stopped → " stopped"`、`waiting → " waiting"`、`failed → " failed"`、`unknown → " —"`。
- **R-AGENT-04** 可见高度最多 5 行，超出在列表内滚动；悬浮显示完整路径和状态。
- **R-AGENT-05** AgentSource 失败只把 Agent list 置为 partial，保留仍可验证的行，MUST NOT 影响计数（R-ARCH-04）。

## 10 额度（F07、F08、PRD 9）

### 10.1 解析

- **R-QUOTA-01** 一个窗口有效当且仅当：`key` 非空；`usedPercent` 为有限数且 ∈ [0, 100]；能得到标签（R-QUOTA-03）。任一不满足 → 该次额度响应视为**格式异常**（不是空额度）。
- **R-QUOTA-02** `remaining = floor(100 − usedPercent)`。
- **R-QUOTA-03** 标签优先级〔据实现，见 Q-02〕：
  1. 来源给出非空权威标签 → 使用之；
  2. `durationMinutes == 10080` → `Weekly remaining`；
  3. 整除 1440 → `{n}-day remaining`；
  4. 整除 60 → `{n}-hour remaining`；
  5. 其他正整数 → `{n}-minute remaining`；
  6. 无标签且无时长 → 窗口无效。
- **R-QUOTA-04** 识别周额度只看 `durationMinutes == 10080`，MUST NOT 依据字段位置（主/次）推断（A22）。当前适配主、次两个窗口，优先 Codex 分组。
- **R-QUOTA-05** 同组内 `key` 重复 → 格式异常。

### 10.2 响应处理

| 响应 | 显示 | 缓存 | Usage 状态 |
| --- | --- | --- | --- |
| 有效且非空 | 实时窗口，阈值颜色 | 覆盖写入 | available |
| 有效且明确为空 | `Usage remaining —`，保留底条 | 覆盖写入（窗口为空） | available |
| 格式异常 | 有同身份缓存 → Saved；否则 `—` | **不写入** | incompatible（有缓存时 saved） |
| 读取失败 / 超时 | 同上 | 不写入 | unavailable（有缓存时 saved） |
| 尚未返回 | 有同身份缓存 → Saved；否则 `—` | — | checking |

### 10.3 颜色与紧凑进度

- **R-QUOTA-06** 实时颜色：`remaining > 40` 绿；`20 < remaining ≤ 40` 橙；`≤ 20` 红。Saved 一律灰。
- **R-QUOTA-07** 紧凑外圈只表达周额度，从顶部中点顺时针沿圆角方形路径绘制，长度 = `remaining / 100`。无周额度 → 只画灰色底圈。
- **R-QUOTA-08** 重置时间悬浮文本格式 `Reset at MMM d, yyyy, h:mm a z`（en_US，本机时区）；缺失为 `Reset at —`。〔据实现〕

### 10.4 缓存

- **R-CACHE-01** 写入条件：身份已验证 **且** 本次额度响应有效（10.2 前两行）。写入内容：`fingerprint, windows, quotaReadAt, lastCompleteSyncAt`。只保留最新一份。
- **R-CACHE-02** 读取条件：`saved.fingerprint == 当前已验证身份.fingerprint`。身份未验证、验证中或不匹配时 MUST 隐藏（不必删除）。
- **R-CACHE-03** Saved 值是冻结的：`resetAt` 过去后 MUST NOT 自动显示 100%，MUST NOT 按时间推算。
- **R-CACHE-04** Saved 显示：标签追加 ` · Saved`，数字与进度灰色；访问性说明 MUST 包含“cached/saved”。
- **R-CACHE-05** 加载时缓存结构不合法（任一窗口无效、key 重复、时间非有限）MUST 丢弃整份缓存。

## 11 紧凑角标（F10、PRD 10.1）

### 11.1 事件记录

CompactTracker 为每个会话最多保存一条 `Entry { runId, kind ∈ {waiting, done}, order }`，`order` 为全局单调计数器。

在**实时**观察转移 `before → after` 时（`before` 存在，且不是基线/恢复）：

```
if entry 存在 且 entry.runId ≠ after.runId: 删除 entry
wasWaiting  = kindOf(before) == waiting
isWaiting   = kindOf(after)  == waiting
replaced    = before.pendingRequestIds 非空 && after.pendingRequestIds 非空
              && 两者不相交
if isWaiting && (!wasWaiting || before.runId ≠ after.runId || replaced):
    entry = { after.runId, waiting, ++order }
elif after.turnStatus == "completed" && (before.turnStatus ≠ "completed" || before.runId ≠ after.runId):
    entry = { after.runId, done, ++order }
```

`kindOf(o)`：classify 为 waitingUser / waitingError → waiting；completed 且 `unread == true` → done；否则无。

### 11.2 角标选择

```
badge :=
  if 计数为 "—": 无
  候选 = { entry | 会话当前 kindOf == entry.kind 且 runId 一致 且 对应计数 > 0 }
  if 候选非空: 返回 order 最大者的 kind
  else baseline: Waiting > 0 → "!"，否则 Done > 0 → "✓"，否则无
```

- **R-BADGE-01** 已读变化、重复快照、元数据补充 MUST NOT 产生新 entry（A35）。
- **R-BADGE-02** 会话离开范围、归档、观察失效时 MUST 删除其 entry。
- **R-BADGE-03** Heartbeat 会话照常参与角标（PRD 10.1）。

## 12 头像休眠（F11、PRD 10.2）

```
asleep := now − lastCodexActivityAt ≥ K-AVATAR-IDLE（30 分钟）
```

- **R-AVATAR-01** 进程启动时 `lastCodexActivityAt := 启动时间`，不恢复上次进程的值。
- **R-AVATAR-02** 只有以下事件更新 `lastCodexActivityAt`：被接受的新实时会话变化；已验证清单的活动变化；当前连接代次内新鲜的 processing 观察。
- **R-AVATAR-03** 以下 MUST NOT 更新：额度查询、内容相同的定时刷新、重复事件、初始或重连基线快照、Waiting/Done 计数保持不变、用户对组件的任何操作。
- **R-AVATAR-04** 判定使用 `≥`：29:59 清醒，30:00 睡眠（A36）。休眠只影响头像图像。

## 13 声音提醒（F12、PRD 11）

### 13.1 事件生成

事件只由**实时连续观察中的状态转移**生成，MUST NOT 由计数差值推导。

| kind | 生成条件（`before → after`，同一会话） |
| --- | --- |
| completed | `before` 属于同一 `runId` 且非 completed，`after.turnStatus == "completed"`；与 `after.unread` 无关（A10） |
| waiting | `kindOf(before) ≠ waiting` 且 `kindOf(after) == waiting`，或 `runId` 变化且新轮次进入 waiting |
| failed | 进入 waitingError 且 `before` 不是 waitingError；`runtime == "active"`（自动重试中）不触发 |

- **R-ALERT-01** 以下情况 MUST NOT 生成事件：`before` 缺失（基线、重连、侧聊接纳、恢复）；`after.isHeartbeat`；用户主动停止（→ stopped）；子 Agent。
- **R-ALERT-02** `occurrence` 去重键：`completed:{conv}:{run}`、`failed:{conv}:{run}`、`waiting:{conv}:{run}:{waitEpisode}`。`waitEpisode` 在每次“离开 waiting 后再进入”时 +1；同一段 waiting 中新增问题、元数据更新、请求记录与等待标记分别到达，MUST 复用同一 `waitEpisode`（A27）。
- **R-ALERT-03** 已消费 `occurrence` 集合的作用域为身份代次；身份变化时清空。集合保留期限见 Q-09。

### 13.2 播放管道

```
receive(event):
  if occurrence 已消费: 丢弃
  标记已消费                                  // 被抑制也算已消费，不形成补播队列
  if allowed() && fresh(event): 入队

advance():                                     // 空闲或上一声结束时调用
  while 队列非空:
    e = 出队
    if !fresh(e): continue                    // 排队不延长有效期
    if output.play(e.kind) 成功启动: 等待完成回调后再 advance; return
    // 启动失败：视为已消费，继续下一项（A32）

fresh(e)   := e.observedAt > discardThrough && now − e.observedAt ≤ K-ALERT-TTL（10 秒）
allowed()  := 已连接 && 身份已验证 && !muted && !systemAsleep && !quitting
              && now − lastMonitorUpdate ≤ K-SNAPSHOT-MAX-AGE
```

### 13.3 取消矩阵

| 触发 | 当前声音 | 队列 | `discardThrough` |
| --- | --- | --- | --- |
| 开启静音 | 立即停止 | 清空 | `= now` |
| 关闭静音 | — | — | `= now`（不补播） |
| 会话失效 / 离开范围 | 属于该会话则停止 | 移除该会话事件 | — |
| 连接代次变化 | 停止 | 清空 | — |
| 身份失效 / 账户或用户切换 | 停止 | 清空，并清空已消费集合 | — |
| 系统睡眠 | 停止 | 清空 | `= now` |
| 退出 | 停止 | 清空，管道关闭 | — |
| 超过 10 秒无新鲜监控更新 | 停止 | 清空 | — |

- **R-ALERT-04** 声音资源：completed = 上行双音，waiting = 重复双音，failed = 下行双音；三者 MUST 可听辨区分（A26）。音量跟随系统，无独立音量。
- **R-ALERT-05** 同一时刻至多一个声音在播放。

## 14 可用性与诊断（F15、PRD 13.4、14）

### 14.1 功能状态

每个功能独立取值 `available | checking | partial | unavailable | incompatible | saved`；`partial / unavailable / incompatible / saved` 视为**降级**。

| 功能 | 规则〔据实现〕 |
| --- | --- |
| Live tasks | 连接或清单失败 → unavailable / incompatible；部分会话观察异常 → `covered > 0 ? partial : incompatible`；初始化中或 `covered == 0 && total > 0` → checking；否则 available |
| Usage | 额度来源失败 → unavailable / incompatible；若已有本次会话读到的额度则改为 saved；从未读到 → checking |
| History recovery | 清单失败或已读/历史来源失败 → 对应失败态；尚未完成首轮 → checking |
| Agent list | 连接或清单失败 → 对应失败态；部分 Agent 数据失败 → partial；否则 available |

### 14.2 底部连接标签（优先级从高到低）

| 顺序 | 条件 | 标签 |
| --- | --- | --- |
| 1 | 存在兼容性问题（关键协议/格式不可解释） | `Incompatible Codex data` |
| 2 | 有可见实时快照（R-AVAIL-02）且任一功能降级 | `Connected · Limited` |
| 3 | 有可见实时快照 | `Connected` |
| 4 | 无可见实时快照，且同身份 Saved 窗口非空 | `Disconnected · Saved usage` |
| 5 | 其他 | `Disconnected` |

该优先级为〔据实现〕，PRD 只列了含义，见 Q-06。

- **R-AVAIL-01** `Connected` MUST NOT 被解读为全范围覆盖；覆盖率只在 Info 中披露。
- **R-AVAIL-02** 可见实时快照：身份匹配、年龄 ≤ 10 秒，且（当前已连接，或连续失败未超过 `K-VISUAL-GRACE` 3 秒）。身份失效、不兼容、明确任务失效不享受 3 秒宽限。
- **R-AVAIL-03** 断开时整体降低饱和度，紧凑头像降低不透明度。
- **R-AVAIL-04** 例外：身份失效会同时隐藏任务、额度（含缓存）和角标，因为 INV-03 优先于 R-ARCH-04。

### 14.3 Info 内容

| 字段 | 取值 |
| --- | --- |
| 连接标签 | 14.2 |
| `Confirmed live conversations: {covered}/{total}` | 第 6 节；restoredDone 不计入 covered |
| 范围说明 | 固定文案：当前账户、本地、未归档、顶层；未同步会话不计入实时统计 |
| 遗留会话 | `unassigned` |
| 四项功能状态 | 名称 + 可读原因 |
| Codex build | 仅诊断用途 |
| `Last complete sync` | 见 R-INFO-01；未知为 `—` |

- **R-INFO-01** 完整同步时间：当一次快照满足 `connected && covered == total && unassigned == 0` 时记录。PRD 3 还要求“无功能降级”，当前实现未检查，且记录的时间值取自额度读取时间而非快照时间，见 Q-01。
- **R-INFO-02** Info 打开时是静态视图，不承诺持续刷新；打开 Info 会展开主面板。

## 15 参数表

所有时间参数 MUST 定义为具名常量，测试中可覆盖。数值是行为基线，不是端到端延迟保证。

| 常量 | 值 | 用途 | PRD |
| --- | --- | --- | --- |
| K-PUBLISH-INTERVAL | 约 1 秒 | 状态向界面发布 | 14.3 |
| K-SNAPSHOT-MAX-AGE | 10 秒 | 可见快照最长年龄；声音健康检查 | 14.3、11.3 |
| K-VISUAL-GRACE | 3 秒 | 普通短暂失败的视觉宽限 | 14.3 |
| K-IDENTITY-INTERVAL | 约 15 秒 | 身份常规复核 | 14.3 |
| K-IDENTITY-RETRY | 约 5 秒 | 身份失败重试 | 14.3 |
| K-IDENTITY-REBUILD | 30 秒 | 持续失败后重建会话 | 14.3 |
| K-INVENTORY-INTERVAL | 约 5 秒 | 清单刷新 | 14.3 |
| K-INVENTORY-GRACE | 30 秒 | 清单失败宽限 | 14.2 |
| K-QUOTA-INTERVAL | 约 60 秒 | 额度刷新 | 14.3 |
| K-QUOTA-RETRY | 约 5 秒 | 额度失败重试 | 14.3 |
| K-HISTORY-INTERVAL | 约 5 秒 | 历史/已读复核 | 14.3 |
| K-HISTORY-DEBOUNCE | 约 250 毫秒 | 变更合并 | 14.3 |
| K-READ-FIRST | 约 1 秒 | 实时 Done 首次已读核对 | 14.3 |
| K-READ-INTERVAL | 约 5 秒 | 实时 Done 后续核对 | 14.3 |
| K-DISCOVERY-RETRY | 约 15 秒 | 来源发现重试 | 14.3 |
| K-BACKOFF | 1, 2, 4, 8, 15, 15… 秒 | 断线退避；健康连接重置 | 14.3 |
| K-ALERT-TTL | 10 秒 | 事件有效期 | 11.2 |
| K-AVATAR-IDLE | 30 分钟 | 休眠阈值 | 10.2 |
| K-SIDECHAT-CAP | 64 | 侧聊候选+接纳上限 | 8.1 |
| K-SIDECHAT-VERIFY-TIMEOUT | 30 秒 | 侧聊验证期限 | 8.1 |
| K-SIDECHAT-RELEASE | 约 2 秒 | 窗口离开宽限 | 8.1 |
| K-DRAG-THRESHOLD | 4 逻辑点 | 进入拖动 | 12.2 |
| K-TOOLTIP-DELAY | 约 350 毫秒 | 悬浮提示 | 4.2 |
| K-DETAILS-ANIM | 约 260 毫秒 | 详情过渡（减少动态效果时为 0） | 4.2 |
| K-LOG-MAX | 1 MiB × 2 文件 | 诊断日志轮转 | 16.3 |

- **R-TIME-01** 年龄与有效期判断 SHOULD 使用单调时钟；显示给用户的时间（重置时间、完整同步时间）使用墙钟。系统睡眠期间单调时钟是否推进由平台决定，唤醒后一律按重连处理（第 18 节），不依赖睡眠期间的计时。

## 16 窗口与交互（F09、PRD 4、12）

### 16.1 布局常量

| 项 | 值（逻辑点） |
| --- | --- |
| 紧凑组件 | 54 × 54，头像约 44 × 44，圆角方形 |
| 展开卡片宽 / 窗口宽 | 320 / 328 |
| 展开头像 | 72 × 72，左外延 8，上外延 28 |
| 工具栏按钮命中区 | 30 × 30；顺序 Pin、Settings、Power |
| 卡片内边距 | 16 |
| `agentsHeight` | `agents == 0 ? 0 : 21 + min(5, agents) × 20` |
| `detailsHeight` | `132 + (max(1, windows) − 1) × 43 + agentsHeight` |
| `cardHeight` | `140 + detailsHeight × detailsProgress`（`detailsProgress ∈ [0,1]`，随动画插值） |
| 设置菜单 | 宽 180，每项 32 |

- **R-UI-01** 展开面板自上而下：头像+工具栏 → 分隔线+Codex 行（右侧详情箭头）→ 额度行 → 三列统计（固定顺序 Processing、Waiting for operation、Done）→ Agent 列表（有行时）→ 底部（左连接标签，右 `Pinned` / `Desktop`）。
- **R-UI-02** 尺寸变化时保持窗口左上锚点；超出可用屏幕区域时平移回可见区域。
- **R-UI-03** 颜色语义：Processing 蓝、Waiting 橙、Done 绿；Done > 0 时展开计数旁显示未读小点。所有状态 MUST 同时有文本/符号/访问性标签。
- **R-UI-04** 外观跟随系统深浅色；减少透明度时使用实底；减少动态效果时详情切换无动画。

### 16.2 窗口层级状态机

```
状态：Desktop（桌面层） | TempFront（临时前置） | Pinned（置顶）

Desktop  ──用户点击/操作组件──────────────► TempFront
TempFront ──用户点击其他应用 / 切换应用────► Desktop
任意      ──Pin────────────────────────────► Pinned
Pinned   ──Unpin（来自本次交互）──────────► TempFront（外部操作后回 Desktop）
任意      ──菜单栏 Show──────────────────► 展开 + TempFront（不改 pinned）
任意      ──菜单栏 Pin/Unpin────────────► 切换 pinned + 展开 + 唤出
面板 Pin 按钮                            ── 只切换 pinned，不改展开形态
```

- **R-WIN-01** 后台更新、提醒、菜单关闭、短暂焦点变化 MUST NOT 触发任何状态转移（INV-09）。
- **R-WIN-02** 展开后点击外部 MUST NOT 自动收起。

### 16.3 拖动与点击

- **R-DRAG-01** 可拖动区：紧凑头像、展开头像、顶部空白、Codex 行非按钮区。按钮与已打开的设置菜单优先于拖动层。
- **R-DRAG-02** 位移 > `K-DRAG-THRESHOLD` 才进入拖动；拖动结束 MUST NOT 同时触发展开/收起；单击须在同一有效区域内按下并释放。
- **R-DRAG-03** 松手后保存 `origin` 与 `displayId`。不吸附边缘，不自动换屏。启动时保存的显示器不存在 → 主屏，并平移到可见区域。

### 16.4 焦点

- **R-FOCUS-01** 被动操作（点击头像、拖动、Pin、展开/收起、详情切换、鼠标操作设置菜单）MUST 保留原应用的键盘焦点。
- **R-FOCUS-02** 主动键盘场景（Keyboard Settings、Info、登录启动错误提示、退出确认）MAY 临时获取焦点；结束后归还给原应用，若期间用户已主动切换到别的应用则不切回。
- **R-FOCUS-03** 点击任务计数或 Open Codex 是显式打开操作，MAY 切到 Codex；只激活应用，不定位会话（A43）。

### 16.5 详情区

- **R-DETAIL-01** 详情隐藏时，隐藏区域 MUST 不可点击，且 MUST 从访问性树移除；动画进行中未稳定显示的统计区域 MUST NOT 响应点击。
- **R-DETAIL-02** 详情隐藏时打开设置菜单 → 先显示详情并保存 `detailsVisible = true`。

## 17 菜单栏与设置（F13、PRD 13）

### 17.1 菜单栏（狐狸尾巴图标，无 Dock 图标）

| 顺序 | 项 | 行为 |
| --- | --- | --- |
| 1 | Show Status Board | 展开 + TempFront |
| 2 | Pin / Unpin Status Board | 切换 pinned + 展开 + 唤出 |
| 3 | Refresh | 立即触发身份、清单、额度、发现、恢复、连接核对；MUST NOT 把旧数据当作刷新成功；MUST NOT 补播声音 |
| 4 | Open Codex | 激活 Codex |
| 5 | Keyboard Settings… | 展开 + 打开设置 + 进入键盘模式 |
| 6 | Info | 打开 Info（并展开面板） |
| 7 | Quit | 进入退出确认 |

### 17.2 面板设置菜单

| 顺序 | 项 | 行为 |
| --- | --- | --- |
| 1 | Mute Sounds（勾选） | 切换 `muted` 并持久化，立即应用 13.3 |
| 2 | Launch at Login（勾选） | 状态**每次打开菜单时从系统读取**；切换时注册/注销 |
| 3 | Info | 打开 Info |
| 4 | Quit | 退出确认 |

- **R-SET-01** 关闭菜单的触发：再次点齿轮、点菜单外、收起面板、选择任一项。关闭菜单 MUST NOT 收起面板。
- **R-SET-02** 键盘模式按键：↑/↓、Tab/Shift+Tab 移动；Home/End 首尾；Enter/Space 执行；Escape 关闭并退出键盘模式。非键盘模式下 MUST NOT 截获原应用按键。
- **R-SET-03** 登录启动需要系统批准 → 提示并打开系统登录项设置。注册/注销失败 → 显示 `Could not update Launch at Login` + 错误信息，然后重新读取系统实际状态。

### 17.3 退出确认

- **R-QUIT-01** 三个入口（面板电源、设置 Quit、菜单栏 Quit）进入同一确认：标题 `Quit Status Board?`，按钮 `Cancel` / `Quit`，默认按钮与回车为 `Cancel`。
- **R-QUIT-02** 已有 Info 或退出确认打开时，MUST NOT 再叠加一个退出确认。
- **R-QUIT-03** 确认后顺序：停止声音 → 停止监控与定时器 → 终止本应用拥有的辅助进程 → 退出。MUST NOT 退出 Codex、停止 Codex 任务或终止其他应用的辅助进程。

## 18 生命周期（F14、PRD 5、15）

| 事件 | 行为 |
| --- | --- |
| 启动 | 单实例检查（重复启动 → 唤出已有实例并退出新实例）→ 菜单栏 → 恢复 Preferences（首次：紧凑、未置顶、未静音、`detailsVisible = true`、不注册登录启动）→ 发现 Codex → 验证身份 → 各来源独立加载 → 首轮数据只建基线 |
| 未发现 Codex | 保留组件与菜单栏；Info 显示 `Codex app not found`；当前版本需重启 Status Board 才会重新发现（见 Q-10） |
| 系统睡眠 | 暂停所有来源；按 13.3 清空声音 |
| 系统唤醒 | 视为连接代次变化：重连、重新验证身份、重建基线；不补播 |
| 身份变化 | 身份代次 +1：丢弃旧观察、旧订阅、旧事件、旧 CompactTracker；隐藏不匹配缓存；新身份静默建基线 |
| 退出 | 17.3 |

- **R-LIFE-01** 只有 `Preferences` 与 `SavedUsage` 跨进程保留；设置菜单打开状态、TempFront、键盘焦点、声音队列、计数、头像计时均不保留。
- **R-LIFE-02** 登录启动状态以系统注册结果为唯一事实来源。

## 19 持久化与日志（PRD 16）

### 19.1 存储

| 数据 | 位置 | 清理 |
| --- | --- | --- |
| Preferences + SavedUsage | 偏好域 `local.statusboard.app` | 退出应用后由用户删除该偏好域（见 Q-11 关于原文措辞） |
| 诊断日志 | `~/Library/Logs/Status Board/diagnostics.jsonl` 及 `.1`，各 ≤ 1 MiB | 用户手动删除 |
| 登录启动 | 系统登录项 | 设置或系统设置关闭 |
| 显式调试输出 | 启用者指定的已有文件 | 启用者负责 |

### 19.2 日志记录约束

- **R-LOG-01** 每条普通日志 MUST 只包含：时间、构建号、固定阶段名、固定事件名、安全错误码、重试次数、恢复耗时、必要的环境版本。
- **R-LOG-02** 普通日志 MUST NOT 包含：原始令牌、账户 ID、会话 ID、账户指纹、正文、原始服务错误文本（A53）。
- **R-LOG-03** 日志写入失败 MUST NOT 影响监控；写满后轮转到 `.1`，总量有界。
- **R-LOG-04** 无任何向维护者服务器的上传、分析或崩溃上报。

## 20 交付（F16、PRD 17）

- **R-REL-01** 交付物：macOS 15.0+、Intel + Apple Silicon 通用 ZIP；附 SHA-256、版本信息、最低系统要求、预览限制；包内含 LICENSE、DISCLAIMER、PRIVACY、THIRD_PARTY_NOTICES、SECURITY。
- **R-REL-02** 发布检查 MUST 在**解压后的交付物**上执行：完整性、架构、资源存在、签名（ad-hoc）。
- **R-REL-03** `--preview-sounds`：顺序播放三种声音后退出；不启动监控、不写偏好、忽略静音设置。
- **R-REL-04** 宣传截图只使用合成数据。

## 21 追溯矩阵

### 21.1 PRD 功能 ↔ SPEC ↔ 验收

| 功能 | SPEC 章节 | PRD 验收 | 建议补充 |
| --- | --- | --- | --- |
| F01 启动与连接 | 1.2、14、18 | A01、A38、A49、A50 | AX-01、AX-02 |
| F02 任务统计 | 4、5、6 | A02、A03、A15、A16 | AX-03 |
| F03 等待识别 | 5.1、5.2 | A04–A08 | AX-04 |
| F04 完成未读恢复 | 7 | A10–A14 | — |
| F05 临时侧聊 | 8 | A18、A19 | AX-05 |
| F06 Agent 活动 | 9 | A20、A44 | — |
| F07 额度 | 10.1–10.3 | A21、A22、A25 | AX-06 |
| F08 额度缓存 | 10.4 | A01、A17、A23、A24 | — |
| F09 桌面面板 | 16 | A39–A42、A45 | AX-07 |
| F10 紧凑状态 | 11 | A34、A35 | — |
| F11 红狐休眠 | 12 | A36、A37 | — |
| F12 声音 | 13 | A26–A33 | AX-08 |
| F13 设置与菜单栏 | 17 | A46–A48 | AX-01 |
| F14 生命周期 | 18 | A38、A45、A33 | AX-02 |
| F15 可用性诊断 | 14、19 | A49–A51、A53 | AX-09 |
| F16 分发与维护 | 20 | A54 | AX-10 |

### 21.2 建议补充的验收用例

PRD 第 18 节 A01–A54 未覆盖、但 SPEC 中有明确规则的行为：

| 编号 | 优先级 | 前置条件与操作 | 通过条件 | SPEC |
| --- | --- | --- | --- | --- |
| AX-01 | P1 | 额度读取失败后点菜单栏 Refresh | 刷新完成前不显示“已刷新”；无补播声音；成功后 Saved 消失 | 17.1 |
| AX-02 | P0 | 有 Processing 时系统睡眠，唤醒期间该任务已完成 | 唤醒后状态更新为真实值，不播放完成音 | 18 |
| AX-03 | P0 | 身份已验证，清单确认为空 | 显示 `0 / 0 / 0` 而非 `—` | R-AGG-01 |
| AX-04 | P0 | 任务 failed 进入 Waiting 后，用户在 Codex 中阅读该会话但不重试 | Waiting 保持（或按 Q-04 的决议） | R-CLASS-05 |
| AX-05 | P1 | 同时出现超过 64 个侧聊候选 | 不崩溃；超出部分不计数；Info 体现部分覆盖 | R-SIDE-02 |
| AX-06 | P1 | 来源同时给出权威标签与 10080 分钟周期 | 显示规则符合 Q-02 的决议；紧凑外圈仍按周额度绘制 | R-QUOTA-03 |
| AX-07 | P2 | 悬浮提示靠近屏幕四边 | 约 350 毫秒后显示，完整可见 | 16.1 |
| AX-08 | P1 | 连续 2 小时产生事件 | 已消费去重集合内存有界 | R-ALERT-03 |
| AX-09 | P1 | 存在功能降级但覆盖率 100% | `Last complete sync` 不更新（或按 Q-01 的决议） | R-INFO-01 |
| AX-10 | P2 | 启动 `--preview-sounds` 且已开启静音 | 三种声音依次播放，偏好文件不变，无监控连接 | R-REL-03 |

## 22 待上游澄清问题

以下问题按影响排序。每项给出 SPEC 当前采用的默认值；上游确认后应回写 PRD 或本 SPEC。

| 编号 | 问题 | PRD 位置 | SPEC 默认值 | 影响 |
| --- | --- | --- | --- | --- |
| Q-01 | “完整同步时间”的建立条件：PRD 3 要求“无功能降级”，当前实现只检查 `covered == total && unassigned == 0`，且记录值取自额度读取时间，而不是本次快照时间 | 3、13.4 | 按实现 | Info 可能在功能降级时仍显示新的完整同步时间；额度缺失时完整同步时间永远不更新 |
| Q-02 | 额度标签：实现会优先使用来源给出的权威标签，PRD 9.1 只写了按时长生成。若来源标签不是 `Weekly remaining`、但时长为 10080，该显示什么？`{n}-day/hour/minute remaining` 格式是否属于产品承诺？ | 9.1 | 按实现 | 文案一致性；A22 |
| Q-03 | “Heartbeat 任务”未在第 3 节术语中定义。实现依据轮次的 `automationKind == "heartbeat"` 判定。是否还有其他自动化类型需要同样抑制声音？ | 10.1、11.3 | 只抑制 heartbeat | 声音范围 |
| Q-04 | 停止失败（failed / systemError）进入 Waiting 后的退出条件 PRD 没写。实现中只有新轮次或离开范围才退出，Codex 已读不会清除。是否符合预期？用户读过失败结果后仍显示 `!` 是否可接受？ | 6.2、7 | 读后不清除 | Waiting 计数可能长期不归零 |
| Q-05 | 范围为空时 PRD 写“可以显示三项 0”。实现为“必须”。建议改成“应”，避免实现之间不一致 | 3.2 | 必须显示 0 | A16 的反向用例 |
| Q-06 | 底部连接标签的优先级（尤其 `Incompatible Codex data` 与 `Disconnected · Saved usage` 同时成立时）未定义 | 14.1 | 第 14.2 节表格 | 标签可预测性 |
| Q-07 | 实现会为已接纳的临时侧聊也显示 `root` 行（`taskIDs = 主会话 ∪ 侧聊`），PRD 8.2 只说“主任务”。是否属于产品承诺？ | 8.2 | 按实现：侧聊也显示 | Agent 行数量；多个 `root` 行的辨识 |
| Q-08 | 侧聊超过 64 个时的行为（拒绝新候选？淘汰旧的？Info 如何披露？）未定义 | 8.1 | 拒绝新候选 + Info 部分覆盖 | 极端场景的正确性 |
| Q-09 | 声音去重集合（已消费的 occurrence）在同一身份下没有过期策略，长期运行会单调增长，与 19.1 “2 小时内存漂移 < 20 MiB”潜在冲突。是否允许按 TTL 或按会话移除时回收？ | 11.2、19.1 | 会话离开范围或轮次超过 1 个之后可回收 | 长期稳定性 |
| Q-10 | 未发现 Codex 时只能重启 Status Board。是否应纳入 K-DISCOVERY-RETRY 周期性重新发现？（PRD 14.3 有“常规来源发现重试 约 15 秒”，与 5.1 表述存在张力） | 5.1、14.3 | 按 5.1：需要重启 | 首次安装体验 |
| Q-11 | 16.3 “应用退出后清除此偏好域”容易被读成“应用退出时会自动清除”。建议改为“先退出应用，再由用户执行 `defaults delete local.statusboard.app`” | 16.3 | 用户手动 | 文档歧义 |
| Q-12 | 计数为 `—` 时，任务计数区域是否仍可点击打开 Codex、是否显示手形指针？ | 5.2、12.5 | 可点击 | 交互一致性 |
| Q-13 | 第 6.1 节第 5 行：`runtime` 非 active（如 idle / notLoaded）但 `turnStatus == inProgress` 时判定为 Processing。这是否与 6.1 末段“历史 inProgress 不足以恢复 Processing”矛盾？需明确“当前有效状态来源”指什么 | 6.1 | 仅当前连接代次的实时观察可产生 Processing（R-CLASS-04） | 误报 Processing |
| Q-14 | 编号命名不一致：2.1 中 F13 为“设置与菜单栏”、F15 为“可用性诊断”；第 20 节索引分别写成“设置与 Info”“数据与诊断” | 2.1、20 | 以 2.1 为准 | 追溯 |
| Q-15 | 验收清单缺少以下行为的用例：菜单栏 Refresh、系统睡眠/唤醒中途发生的状态转移、`--preview-sounds`、悬浮提示定位、空范围显示 0。建议吸收第 21.2 节 AX-01–AX-10 | 18 | — | 验收完整性 |
