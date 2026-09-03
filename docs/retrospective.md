---
title: Typeless 付费弹窗自动关闭：排查与实现复盘
aliases: [typeless paywall closer, Typeless 去弹窗]
tags: [macos, hammerspoon, accessibility, electron, retrospective]
type: note
created: 2026-09-03
updated: 2026-09-03
status: evergreen
summary: 评估第三方闭源工具后自己用 Hammerspoon 写了只关两条付费弹窗的脚本，记录 Typeless 内部机制、三个不在文档里的坑和与 Codex 版的对比
---
# Typeless 付费弹窗自动关闭：排查与实现复盘

## 背景

Typeless（macOS 语音输入，Electron 应用）免费版超过约 2000 字后会在悬浮条弹出
"Upgrade for enhanced accuracy" 的付费卡片，点 × 只关本次。目标是自动关掉这一条，
不碰更新、报错等其他提示。

## 结论

- 第三方工具 `liuxiaoyu-fiveleven/Typeless-AD-Skipper` 不建议用：闭源、ad-hoc 签名未公证、
  需要辅助功能权限、二进制里有反调试逻辑。静态分析旧版没发现联网和持久化，但无法审计。
- 自己写的 Hammerspoon 脚本已在真实弹窗上验证通过。代码在
  `~/ClaudeCode/typeless-paywall-closer`，私有仓库 `TIAN-TOM/typeless-paywall-closer`。

## 第三方工具评估方法

1. `gh repo view` 看 star、fork、license、语言。仓库只有 README，24 次 commit 全是改 README。
2. `git log --all --name-status` 发现历史里提交过又删掉的 `v1.0.0.dmg`，`git cat-file -p` 取出来只读挂载。
3. `codesign -dv`、`spctl --assess`、`otool -L`、`strings` 做静态检查。关键发现：
   `Debugger attachment detected; terminating`、调用 `/usr/bin/tccutil` 重置自身 TCC 授权、
   没有 URL 和网络框架字符串。
4. 结论基于旧版，最新 DMG 没有下载，不能替它背书。

## Typeless 内部机制（2.5.0）

- Electron 33，主进程代码经 javascript-obfuscator 混淆，渲染层是 Vite 分包。
- 悬浮条窗口标题 "Status"，`type: 'panel'`，透明 750×500 画布，空闲时只有十几个 AX 节点。
- 弹窗文案不在本地包里。`/ai/voice_flow` 返回带 `important_notification` 时客户端标记为
  `paywall`，走 `onSessionInterrupt` 渲染成悬浮条里的 MUI Tooltip 卡片（`role="tooltip"`，
  AX 子角色 `AXUserInterfaceTooltip`）。
- 卡片 `closable` 时右上角挂一个无 `aria-label` 的 `IconButton`，内含 16px `CloseIcon`。
- 不解包读 `app.asar`：文件头 16 字节后是 JSON 目录，数据区偏移为 `8 + header pickle size`。
  脚本在项目 `tools/` 下。

## 三个不在文档里的坑

1. **授权后必须重启 Hammerspoon**。运行中授予辅助功能权限后，对已运行的 Typeless 发 AX 请求
   一直返回 "The accessibility API is disabled"，而 Finder 正常。`hs.relaunch()` 后恢复。
2. **Electron 需要 `AXManualAccessibility = true`** 才暴露网页树。`AXEnhancedUserInterface`
   是同一个开关，设为 false 会把整棵树关掉。
3. **Chromium 不发内容变化的 AX 通知**。注册了 90 种通知一条没收到。0.5 秒轮询是唯一可靠触发。

## 最终方案

- 用 Bundle ID `now.typeless.desktop` 挂载，轮询宽度不超过 900px 的窗口（设置主窗口至少 988 宽）。
- 精确匹配 `AXStaticText` 值，向上找 `AXUserInterfaceTooltip` 容器，只在容器内选无名、
  边长不超过 40px、最靠右上角的 `AXButton`，`AXPress`。带文字的按钮永远不点。
- `hs.autoLaunch(true)` 登录自启，`Ctrl+Alt+Cmd+T` dump 树到控制台。

## 验证记录

- 2026-09-03 12:49:49 首次真实弹窗被 AXPress 关闭，按钮 16×16，容器 tooltip，下一次扫描卡片消失。

## Typeless 升级后失效怎么办

1. `hs -c 'typeless.dump()'` 看卡片出现时的树。
2. 文案变了改 `targetTitles`；结构变了改 `alertContainer` / `pickCloseButton`。
3. 用 `tools/asar_scan.js` 搜新版 `app.asar` 确认字段名。

## 附带观察

- 作者在 V2EX 自述配合切号绕免费额度，脚本本身只关卡片，切号大概率违反服务条款。
- Homebrew cask 装的 Hammerspoon 首次启动会有 Gatekeeper 确认框，必须手动点。

## 来源

- [Typeless-AD-Skipper 仓库](https://github.com/liuxiaoyu-fiveleven/Typeless-AD-Skipper)
- [V2EX 讨论帖](https://www.v2ex.com/t/1225542)
- [Electron accessibility 文档](https://www.electronjs.org/docs/latest/tutorial/accessibility)
- [hs.axuielement 文档](https://www.hammerspoon.org/docs/hs.axuielement.html)

## 后续改动（2026-09-03 下午）

- 对比了 Codex 写的原生 Swift 版本。它没有设置 `AXManualAccessibility`，右上角判断以整个 750×500 透明画布为参照，
  用 12:49:49 的真实坐标代入两条规则都不通过，所以关不掉真实弹窗。但它有四点值得借鉴，已全部搬进 Hammerspoon 版。
- 新增第二个目标 "High demand"，卡片结构与第一种完全相同。
- 候选按钮必须在 `actionNames` 里有 `AXPress`；菜单栏 `⌧` 图标带暂停开关和状态；动作与警告写入
  `~/Library/Logs/typeless-paywall-closer/activity.log`；匹配逻辑抽成 `M.matcher` 纯函数，`selfTest()` 启动自跑。
- 重写后的代码于 17:24:08 再次在真实弹窗上验证通过，AXPress 预检查通过。累计真实关闭 3 次，未触发过鼠标模拟。
- Obsidian 已改为 Homebrew cask 管理。应用层由 Obsidian 自带更新器静默升级；外壳层需要时手动
  `brew upgrade --cask --greedy obsidian hammerspoon`，未设定时任务。
