<div align="center">

# Typeless Paywall Closer

**让 Typeless 悬浮条上的付费提示卡片自动消失，其余一概不动。**

[![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)](#系统要求)
[![Runs on Hammerspoon](https://img.shields.io/badge/runs%20on-Hammerspoon-4c9be8)](https://www.hammerspoon.org)
[![Verified on Typeless 2.5.0](https://img.shields.io/badge/verified%20on-Typeless%202.5.0-2f7d32)](#已验证的事实)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

[English](README.md) · 简体中文

</div>

---

Typeless Paywall Closer 是一个小巧、可审计的 macOS 工具。Typeless 悬浮条里的两种付费卡片
**"Upgrade for enhanced accuracy"** 和 **"High demand"** 一旦渲染出来，它就通过 macOS 辅助功能 API
按下卡片自带的关闭按钮，和你手动点 × 完全一样。不改应用本体，不拦截流量，不联网。

取舍很直白：卡片会闪现一瞬再消失，通常不到 0.2 秒。换来的是 Typeless 原封不动、升级后照常工作，
以及一份你能逐行读完的代码。

## 特性

- **只关两条。** 精确匹配两条标题。更新提示、报错和其他任何卡片都不碰。
- **零侵入。** 不改 `app.asar`，不动签名，不架本地代理。只要卡片结构不变，Typeless 升级后继续可用。
- **常驻不掉线。** launchd 守护 Hammerspoon：退出或崩溃几秒内自动拉起，开机登录自动启动。
- **省电。** 只在麦克风使用中（以及停用后 30 秒内）每 0.05 秒扫一次，空闲时每 2 秒兜底一次。
- **状态可见。** 菜单栏图标显示权限、挂载、扫描档位和最近一次关闭。日志只记关闭、警告和启动事件。
- **自检。** 每次启动自动用假数据跑一遍匹配规则和调度逻辑，失败写入日志。
- **隐私优先。** 从悬浮条读到的文字只用来和目标标题比较，比完即弃，不存不传。

## 快速开始

需要 macOS 和 [Homebrew](https://brew.sh)。

```bash
git clone https://github.com/TIAN-TOM/typeless-paywall-closer.git && cd typeless-paywall-closer && ./install.sh
```

安装脚本会：

1. 没有 Hammerspoon 就用 Homebrew 装上。
2. 把脚本符号链接进 `~/.hammerspoon`，往 `init.lua` 追加启动代码。
3. 渲染并加载 launchd 代理 `org.hammerspoon.keepalive`，把 Hammerspoon 进程交给 launchd 接管。
4. 打开系统设置的辅助功能页。

然后一次性做三件事：

1. macOS 询问是否打开 Hammerspoon 时，点 **打开**。
2. 在 **系统设置 › 隐私与安全性 › 辅助功能** 里打开 **Hammerspoon**。
3. 退出并重新打开 Hammerspoon。不重启的话，辅助功能 API 会拒绝对已运行的 Typeless 发出的请求。

菜单栏出现 `⌧` 图标，安装就完成了。

**更新：** `git pull` 后再跑一次 `./install.sh`。**卸载：** `./install.sh uninstall`，Hammerspoon 本身会保留。
**不要 launchd 守护：** `KEEPALIVE=0 ./install.sh`，Hammerspoon 只靠登录项启动。

<details>
<summary>手动安装</summary>

```bash
brew install --cask hammerspoon
ln -s "$PWD/typeless_paywall_closer.lua" ~/.hammerspoon/typeless_paywall_closer.lua
```

`~/.hammerspoon/init.lua` 里加：

```lua
require("hs.ipc")
hs.autoLaunch(true)
typeless = require("typeless_paywall_closer")
typeless.start()
```

可选但推荐的 launchd 守护：

```bash
sed "s|__HOME__|$HOME|g" launchd/org.hammerspoon.keepalive.plist > ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
```

在系统设置里给 Hammerspoon 授权辅助功能，然后**退出并重开一次 Hammerspoon**。
不重启的话，所有对 Typeless 的 AX 请求都会返回 "The accessibility API is disabled"。

</details>

## 系统要求

| | |
|---|---|
| 系统 | macOS（在 macOS 26 / Darwin 25 上测试） |
| 运行时 | [Hammerspoon](https://www.hammerspoon.org)，由 `install.sh` 安装 |
| 目标应用 | Typeless 桌面版，Bundle ID `now.typeless.desktop`，已在 2.5.0 验证 |
| 权限 | 辅助功能，授予 Hammerspoon |

## 菜单栏

`⌧` 图标包含日常需要的一切：

- **Enabled / Paused。** 暂停后停止扫描，进程仍保持挂载。
- **状态行。** 辅助功能是否授权、Typeless 是否挂载（含 pid）、当前扫描档位、最近一次关闭和本次会话关闭次数。
- **操作。** Scan now、Dump AX tree to console、Open log file、缺权限时的 Open Accessibility settings、Reload Hammerspoon。

暂停时图标变为 `⌧∙`。

## 常驻守护

Hammerspoon 可能被手动退出、被内存压力杀掉，或者崩溃后没人拉起。登录项只在登录时生效，
白天退出一次就要等到下次重启才有保护。所以安装脚本注册了一个用户级 LaunchAgent：

| 项 | 值 |
|---|---|
| Label | `org.hammerspoon.keepalive` |
| 文件 | `~/Library/LaunchAgents/org.hammerspoon.keepalive.plist`，由 [`launchd/`](launchd/) 里的模板渲染 |
| 行为 | `RunAtLoad` + `KeepAlive`，重启间隔 5 秒 |
| launchd 输出 | `~/Library/Logs/typeless-paywall-closer/hammerspoon-launchd.log` |

需要知道的影响：

- 从 Hammerspoon 菜单 **Quit** 会在几秒内被拉回来。要真正停掉：

  ```bash
  launchctl bootout gui/$(id -u)/org.hammerspoon.keepalive
  ```

- 重新启用：

  ```bash
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
  ```

- **Reload Config** 不受影响，它只在进程内重载 Lua。
- 如果 Hammerspoon 启动即崩溃，launchd 每 5 秒重试一次，原因看 launchd 日志。

## 隐私与安全

脚本需要辅助功能权限，这个权限原则上允许读取任何应用的界面。实际上它只读 Typeless 悬浮条窗口里的文字，
用来和目标标题比较，比完即丢弃。听写过程中悬浮条可能显示实时转写，这些文字不会被记录、存储或发送。
活动日志里只有匹配到的标题、关闭按钮的位置和时间。

脚本不发任何网络请求，除了自己的日志文件不写任何东西。整个产品约 650 行 Lua，
设计初衷就是先读再信。

## 工作原理

1. **挂载。** 用 Bundle ID 找到 Typeless 进程，对 application 元素设 `AXManualAccessibility = true`，
   否则 Chromium 不在辅助功能树里暴露网页内容。所有 AX 调用带 1 秒超时，Typeless 卡死不会拖住 Hammerspoon。
2. **轮询。** Chromium 不会为内容变化发出可用的 AX 通知（注册了 90 种一条都收不到）。扫描节奏跟着麦克风走：
   任一输入设备在用时，以及停用后的 30 秒内，每 0.05 秒扫一次；其余时间每 2 秒。
   付费卡片只随一次听写的响应到达，空闲时不值得高频扫。
3. **选窗口。** 只扫子角色为 `AXDialog` 的窗口。悬浮条是 Electron panel 窗口，标题 "Status"，750×500，
   空闲时只有十几个节点。设置、登录和引导窗口是 `AXStandardWindow`，直接跳过。没有子角色的窗口退回宽度判断（≤ 900 px）。
4. **找卡片。** 找到值等于目标标题的 `AXStaticText`，向上找到 `AXUserInterfaceTooltip` 容器
   （对应 HTML `role="tooltip"`），只在容器内找按钮。
5. **按 ×。** 候选按钮必须支持 `AXPress`、无名或名为 close / dismiss / x / ×、边长不超过 40 px。
   多个候选取最靠容器右上角的那个。"Upgrade" 这类文字按钮永远不会被点。默认不做鼠标模拟；
   `clickFallback = true` 只在 `AXPress` 被拒绝时退化为模拟点击。

所有阈值都在 `typeless_paywall_closer.lua` 顶部的 `config` 表里，也可以运行时通过 `typeless.config` 修改。

## 已验证的事实

Typeless 2.5.0，2026-09-03 观察：

- 卡片文案不在本地包里。服务端在 `/ai/voice_flow` 返回里附带 `important_notification`，
  结构是 `{type: "paywall", display: {title, description, icon}, behavior, actions}`。
  `icon` 是 `diamond`（Upgrade for enhanced accuracy）或 `sandglass`（High demand）。
  所以在 `app.asar` 里改字符串没用；把两处 `paywall` 调用打成空操作可行，但要打补丁、重签名，每次更新后重来。本项目刻意不走这条路。
- 卡片是 MUI Tooltip。`closable` 时右上角有一个 `IconButton`，内含 16 px `CloseIcon`，没有 `aria-label`。两种卡片结构相同。
- `AXEnhancedUserInterface` 和 `AXManualAccessibility` 是同一个开关，把前者设 false 会关掉整棵树。
- 真实卡片多次被 `AXPress` 成功关闭，按钮 16×16，容器为 tooltip。鼠标模拟从未触发。
- `targetTitles` 另含 2.4.0 时期的 `Get unlimited words` / `获取无限字数`，来自 typeless-plusplus 的记录，本机未见过。
  精确匹配整段标题，所以就算永远不出现也无害。

## 故障排查

| 现象 | 检查 |
|---|---|
| 卡片没被关掉 | `pgrep -x Hammerspoon`。没有进程就看 `launchctl print gui/$(id -u)/org.hammerspoon.keepalive` 和 launchd 日志。 |
| 菜单显示 *Accessibility: missing* | 在 系统设置 › 隐私与安全性 › 辅助功能 里打开 Hammerspoon，然后退出并重开 Hammerspoon。 |
| 菜单显示 *Typeless: not running* | Typeless 没在运行，或者 Bundle ID 变了。`hs -c 'typeless.dump()'` 列出当前可见的内容。 |
| Typeless 升级后卡片留着 | 卡片显示时跑 `hs -c 'typeless.dump()'`，对照调整 `config`、`alertContainer` 或 `M.matcher.chooseCloseButton`。文案变了就补 `targetTitles`，最后跑 `hs -c 'typeless.selfTest()'`。 |
| Typeless 界面是其他语言 | 付费文案按账号语言下发。把对应语言的标题加进 `targetTitles`。 |

调试命令，需要 `hs.ipc` 已加载：

```bash
hs -c 'typeless.dump()'
```

```bash
hs -c 'typeless.selfTest()'
```

```bash
hs -c 'typeless.micInUse()'
```

```bash
hs -c 'typeless.log.setLogLevel("debug")'
```

⌃⌥⌘T（Control+Option+Command+T）打开控制台并 dump 一次。成功关闭时日志里有一行 `closed "…" via AXPress`。

## 同类项目

| 项目 | 思路 | 平台 | 取舍 |
|---|---|---|---|
| [JeasonKim/typeless-paywall-gateway](https://github.com/JeasonKim/typeless-paywall-gateway) | 用隐藏设置 `__DEV_API_HOST` 把 API 指到本地代理，改写返回里的 `paywall` 通知 | macOS、Windows | 卡片完全不出现，不需要辅助功能权限；但全部语音和转写流量经过本地代理，依赖一个官方随时可能删掉的隐藏开关，安装要 Node 和 pnpm |
| [Ayndpa/typeless-popup-remover](https://github.com/Ayndpa/typeless-popup-remover) | 改 `app.asar` 让弹窗渲染函数直接 return，并关掉 Electron 完整性校验 | Windows | 卡片完全不出现；但修改了应用本体，每次升级都要重打补丁 |
| [timmyagentic/typeless-plusplus](https://github.com/timmyagentic/typeless-plusplus) | 原生 Swift 菜单栏 App，同样走辅助功能树点 ×，另做账号管理和额度守护 | macOS | 开源、MIT、有公证；但源码没有设置 `AXManualAccessibility`，作者自述真实弹窗尚未验证 |
| [Jia131313/typeless-toolkit](https://github.com/Jia131313/typeless-toolkit) | 扫描 `app.asar`，把处理 `paywall` 的两处调用等长替换成空操作，同步完整性校验并重签名 | macOS、Windows | 生态里 star 最多，功能是多账号、词库同步、设备重置的超集；卡片完全不出现，但修改应用本体，每次官方更新后要重打 |
| [liuxiaoyu-fiveleven/Typeless-AD-Skipper](https://github.com/liuxiaoyu-fiveleven/Typeless-AD-Skipper) | 辅助功能树里找卡片点 ×，和本项目同路 | macOS | 闭源，ad-hoc 签名未公证，二进制带反调试 |

本项目选择"渲染后立即关掉"，因为信任面最小：不改包、不拦流量。如果闪动不可接受，
gateway 和 toolkit 是能做到卡片不出现的开源方案，代价分别是本地代理和修改应用本体。

## 仓库结构

| 路径 | 作用 |
|---|---|
| `typeless_paywall_closer.lua` | 全部逻辑。`~/.hammerspoon/typeless_paywall_closer.lua` 是指向它的符号链接，改完 `hs.reload()` 生效 |
| `install.sh` | 安装、更新、卸载，可重复执行 |
| `launchd/org.hammerspoon.keepalive.plist` | LaunchAgent 模板，`__HOME__` 由安装脚本渲染 |
| `init.lua.example` | `~/.hammerspoon/init.lua` 参考内容 |
| `tools/asar_scan.js` | 不解包直接在 Typeless 的 `app.asar` 里搜字符串并打印上下文 |
| `tools/asar_extract.js` | 把 `app.asar` 的 `dist/` 解到当前目录的 `typeless_dist/` |
| `tools/cgwin.swift` | 用 CGWindowList 列出 Typeless 的所有窗口，不需要辅助功能权限 |
| `docs/retrospective.md` | 排查与实现复盘 |
| `CHANGELOG.md` | 版本记录 |

日志：`~/Library/Logs/typeless-paywall-closer/activity.log`（脚本）和 `hammerspoon-launchd.log`（launchd）。

## 参与贡献

欢迎 Issue 和 Pull Request，尤其是 Typeless 升级后的辅助功能树 dump，以及其他界面语言的目标标题。
提交 PR 前跑一遍 `hs -c 'typeless.selfTest()'`，必须全部通过。

## 许可证

[MIT](LICENSE)。
