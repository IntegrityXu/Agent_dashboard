# 第三方资源与素材声明

更新日期：2026-10-26。范围：本仓库及 Status Board 0.2.1 build 38 使用的已识别资源。

**项目自有代码采用 MIT；这不意味着仓库中的所有材料都获得 MIT 授权。Joker、皇冠和衍生应用图标的授权目前待核实，不作“完全原创”或“已清除全部第三方权利”的声明。**

## 1. 项目许可范围

除本文件或相邻文件另有说明外，维护者有权授权的项目自有源代码、脚本、文档及由项目脚本生成的提示音采用根目录 [MIT License](LICENSE)。该许可允许商业使用；项目当前不收费不构成额外的非商业限制。

第三方材料保留其原有许可。商标及其他第三方权利不因项目采用 MIT 而转移。本文件不会授予维护者本身没有的权利。

## 2. 应用随附的图片：授权待核实

维护者提供的来源说明为：**使用 AI 生成或基于参考图修改**。尚未逐项确认具体生成工具/模型、生成日期、参考图来源、参考图权利和可再分发条款。

| 文件 | 当前用途与来源记录 | 授权状态 |
| --- | --- | --- |
| `StatusBoard/Resources/joker_right.png` | Joker 头像；AI 生成或基于参考图修改，具体来源链待补齐 | **待核实；暂不纳入本项目 MIT 授权** |
| `StatusBoard/Resources/crown.png` | 菜单栏皇冠图标；AI 生成或基于参考图修改，具体来源链待补齐 | **待核实；暂不纳入本项目 MIT 授权** |
| `StatusBoard/Resources/AppIcon.icns` | 通过 `scripts/generate-app-icon.sh` 从 Joker 图片生成多个图标尺寸 | **随源图授权一并待核实；暂不纳入本项目 MIT 授权** |

AI 生成或修改不自动证明参考图、人物/角色形象、标识及其他元素不存在第三方权利。“待核实”只是当前记录状态，不是已取得许可的证明，也不能消除已经分发这些素材可能涉及的义务或责任。

当前 build 38 发布包包含上述素材。不能仅凭代码的 MIT License 推断已获这些图片的使用、再分发或再许可权；要制作许可范围明确的衍生分发包，应先取得所需授权或替换为权利清晰的资源，并重新生成衍生图标。

后续核实时，应记录生成服务及当时适用的条款、参考图来源/作者/许可、修改过程、署名要求和授权凭据。需要署名的材料应保留实际要求，不能用“侵权联系删除”代替许可。

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

对有权分发的项目材料，请遵守对应许可证的版权和许可保留要求。图片权利待核实与 MIT 代码的可用性是不同事项；本文件不将图片权利不确定性改写成对 MIT 代码的非商业、不可修改等附加限制。

维护者制作后续发行包时，应随包提供适用的许可证和说明，保持文件清单与实际资源一致。已经发布的 build 38 ZIP 未随附本轮新增文档；仓库文档更新不会自动改写该 ZIP 或其校验值。

如果你认为某项资源的来源、版权或授权记录有误，可通过 [Issues](https://github.com/IntegrityXu/Agent_dashboard/issues) 提供不含私人材料的说明。需要提交非公开授权凭据时，先请求私密联络方式，勿公开上传证件、合同或个人信息。收到异议后应核对并按具体情况更正、替换或采取其他必要措施；这里不预先断言存在或不存在侵权。
