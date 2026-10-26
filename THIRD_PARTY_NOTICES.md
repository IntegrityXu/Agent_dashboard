# 第三方资源与素材声明

更新日期：2026-10-26。范围：本仓库及 Status Board 0.2.2 build 39 使用的已识别资源。

**项目自有代码及维护者有权授权的当前红狐素材按 MIT 提供；第三方材料保留原有许可。旧版 Joker、皇冠及其衍生图标的授权记录仍为待核实，不适用于当前红狐素材。**

## 1. 项目许可范围

除本文件或相邻文件另有说明外，维护者有权授权的项目自有源代码、脚本、文档、当前红狐素材及由项目脚本生成的提示音采用根目录 [MIT License](LICENSE)。该许可允许商业使用；项目当前不收费不构成额外的非商业限制。

第三方材料保留其原有许可。商标及其他第三方权利不因项目采用 MIT 而转移。本文件不会授予维护者本身没有的权利。

## 2. 当前红狐素材与旧版素材

### 当前版本：GPT 生成的红狐素材

维护者于 2026-10-26 确认：**下列红狐素材均使用 GPT 创作，未参考已有图片。** 这是维护者提供的来源记录，不表述为人工绘制或经过独立权利审查。具体模型版本、生成时间和生成会话未在仓库公开记录。

| 文件 | 用途与来源 | 项目提供的许可 |
| --- | --- | --- |
| `StatusBoard/Resources/fox-red.svg` | GPT 生成的清醒红狐悬浮头像 | 维护者有权授予的权利按 MIT 提供 |
| `StatusBoard/Resources/fox-red-sleeping.svg` | GPT 生成的睡眠红狐头像，连续空闲 30 分钟后使用 | 同上 |
| `StatusBoard/Resources/fox-red-head.svg` | GPT 生成的红狐头部，应用图标源图 | 同上 |
| `StatusBoard/Resources/fox-tail-open-ring.svg` | GPT 生成的狐狸尾巴，菜单栏图标 | 同上 |
| `StatusBoard/Resources/AppIcon.icns` | 由 `scripts/generate-app-icon.sh` 从当前红狐头部源图生成 | 同源图，维护者有权授予的权利按 MIT 提供 |

维护者将其对上述素材及项目加工结果有权授予的权利纳入根目录 MIT 许可，不附加非商业限制。AI 输出不一定具有独占性；本说明不保证每个地区均承认其著作权，也不授予潜在第三方的商标或其他权利。[OpenAI 使用条款](https://openai.com/policies/terms-of-use/) 的内容权属条款以适用法律允许为限，并说明不同用户可能获得相似输出；生成服务的实际适用条款以生成时的账户、地区与服务为准。

### 历史版本：Joker、皇冠和旧应用图标

`0.2.1 build 38 / v0.2.1-preview.38` 及其历史源码使用 `joker_right.png`、`crown.png` 和基于 Joker 生成的 `AppIcon.icns`。维护者此前提供的来源说明为“使用 AI 生成或基于参考图修改”；这些旧素材的授权仍待核实，仍不纳入项目 MIT 授权。

自 **0.2.2 build 39** 起，旧 Joker 和皇冠图片从当前源码与新应用包中移除，应用图标改由红狐源图生成。当前素材的新来源说明不追溯改变旧素材的权利状态；旧 Git 历史、标签与 Release 仍可能包含它们。分发旧版本或历史源码时，应另行核实旧素材的所需权利。“待核实”不是已取得授权的证明。

## 3. SQLite：当前应用随附

- 组件：SQLite 3.54.1 上游 amalgamation。
- 源文件：`Packages/StatusBoardCore/Sources/StatusBoardSQLite/vendor/sqlite3.c` 与 `include/sqlite3.h`。
- 上游：[SQLite](https://www.sqlite.org/)；[公有领域说明](https://www.sqlite.org/copyright.html)。
- 本地版本、下载源和校验记录：[vendor/README.md](Packages/StatusBoardCore/Sources/StatusBoardSQLite/vendor/README.md) 及 [upstream.json](Packages/StatusBoardCore/Sources/StatusBoardSQLite/vendor/upstream.json)。

SQLite 官方将可分发代码和文档贡献至公有领域；其上游声明保留在源文件开头。不要将这些上游文件的权属改写为本项目作者所有。项目另外提供符号命名空间封装和构建配置；上游源码的许可状态不由根目录 MIT 改变。

## 4. Liquid-TUI：仅用于归档实验

- 上游：[Pugbread/Liquid-TUI](https://github.com/Pugbread/Liquid-TUI)。
- 版权：Copyright (c) 2026 Pugbread。
- 许可：MIT；完整原文保存在 [Archive/DesktopLens/Liquid-TUI/LICENSE](Archive/DesktopLens/Liquid-TUI/LICENSE)。
- 引用范围和说明：[归档参考记录](Archive/DesktopLens/Liquid-TUI/README.md)。

`Archive/DesktopLens/` 的历史实验参考和适配了该项目的屏幕捕获/Metal 架构及部分渲染方法。归档代码不参与当前生产应用构建。再分发包含这些代码的仓库副本或衍生实验时，需按其许可保留上游版权和许可文本；不能因当前应用未使用而删除源码分发中的必要说明。

## 5. 提示音

`Packages/StatusBoardCore/Sources/StatusBoardDesktop/Resources/` 下的 `completed.wav`、`waiting.wav`、`failed.wav` 由 [scripts/generate-alert-sounds.py](scripts/generate-alert-sounds.py) 按数值波形生成，脚本未读取第三方录音或音乐采样。项目对其有权授予的权利随 MIT 提供；不据此作出全球范围的独占性或无侵权保证。

## 6. Apple / OpenAI 组件、名称和图标

当前应用使用系统提供的 SwiftUI、AppKit、ServiceManagement 等框架和系统符号。相关系统组件受其适用条款约束，不因本项目采用 MIT 而成为本项目自有资产。

运行时从本机安装的 Codex 应用读取其图标，并调用其自带的 Codex CLI 辅助程序。当前发布包不随附 OpenAI 的 Codex 应用或 CLI 二进制。OpenAI、Codex、ChatGPT、Apple、macOS 及相应标识的权利属于各自权利人；兼容性引用不表示官方授权、合作、背书或商标许可。

## 7. 再分发与后续核实

对有权分发的项目材料，请遵守对应许可证的版权和许可保留要求。旧版图片权利待核实与当前 MIT 材料的可用性是不同事项；本文件不将历史图片权利不确定性改写成对 MIT 代码的非商业、不可修改等附加限制。

自 build 39 起，发行应用的 `Contents/Resources/Legal/` 随附 LICENSE、DISCLAIMER.md、PRIVACY.md、THIRD_PARTY_NOTICES.md 和 SECURITY.md。已经发布的 build 38 ZIP 未随附这些文档；仓库文档更新不会自动改写旧 ZIP 或其校验值。

如果你认为某项资源的来源、版权或授权记录有误，可通过 [Issues](https://github.com/IntegrityXu/Agent_dashboard/issues) 提供不含私人材料的说明。需要提交非公开授权凭据时，先请求私密联络方式，勿公开上传证件、合同或个人信息。收到异议后应核对并按具体情况更正、替换或采取其他必要措施；这里不预先断言存在或不存在侵权。
