# typeless-paywall-closer

Hammerspoon 脚本，自动关闭 Typeless（macOS，Electron）悬浮条里标题为
**"Upgrade for enhanced accuracy"** 的付费提示卡片。只处理这一条，不碰其他通知。

## 文件

| 文件 | 作用 |
|---|---|
| `typeless_paywall_closer.lua` | 全部逻辑。`~/.hammerspoon/typeless_paywall_closer.lua` 是指向它的符号链接，改完直接 `hs.reload()` 生效 |
| `init.lua.example` | `~/.hammerspoon/init.lua` 的参考内容 |
| `tools/asar_scan.js` | 不解包直接在 Typeless 的 `app.asar` 里搜字符串并打印上下文 |
| `tools/asar_extract.js` | 把 `app.asar` 的 `dist/` 解到当前目录的 `typeless_dist/` |
| `tools/cgwin.swift` | 用 CGWindowList 列出 Typeless 的所有窗口，不需要辅助功能权限 |

## 安装

```bash
brew install --cask hammerspoon
```

```bash
ln -s "$PWD/typeless_paywall_closer.lua" ~/.hammerspoon/typeless_paywall_closer.lua
```

`~/.hammerspoon/init.lua` 里加：

```lua
require("hs.ipc")
hs.autoLaunch(true)
typeless = require("typeless_paywall_closer")
typeless.start()
```

然后在 系统设置 > 隐私与安全性 > 辅助功能 里打开 Hammerspoon。
**授权之后必须重启一次 Hammerspoon**，否则对已运行的 Typeless 发 AX 请求会一直返回
"The accessibility API is disabled"。

## 调试

```bash
hs -c 'typeless.dump()'
```

```bash
hs -c 'typeless.log.setLogLevel("debug")'
```

快捷键 `Ctrl+Alt+Cmd+T` 会打开控制台并 dump 一次。成功关闭时控制台会有一行
`closed paywall card via AXPress`。

## 工作原理

1. 用 Bundle ID `now.typeless.desktop` 找到进程，对 application 元素设
   `AXManualAccessibility = true`，否则 Chromium 不暴露网页内容的 AX 树。
2. 每 0.5 秒扫一次宽度不超过 900px 的窗口。悬浮条窗口标题是 "Status"，750×500，
   空闲时只有十几个节点。设置主窗口至少 988 宽，会被跳过。
3. 找到 `AXStaticText` 的值等于目标标题后，向上找到 `AXSubrole == AXUserInterfaceTooltip`
   的容器（对应 HTML `role="tooltip"`），只在容器内找按钮。
4. 只点无名、边长不超过 40px、最靠右上角的那个 `AXButton`（16×16 的 X 图标）。
   带文字的按钮如 "Upgrade" 永远不会被点。AXPress 失败才退化为模拟点击。

## 已验证的事实（Typeless 2.5.0，2026-09-03）

- 弹窗文案不在本地包里。服务端在 `/ai/voice_flow` 返回里带 `important_notification`，
  客户端标记为 `paywall`，交给悬浮条渲染。改本地包没用。
- 卡片组件是 MUI Tooltip，`closable` 时右上角挂一个 `IconButton`，内含 16px `CloseIcon`，
  没有 `aria-label`。
- 注册了 90 种 AX 通知，Chromium 一条都不发。轮询是唯一可靠的触发方式。
- `AXEnhancedUserInterface` 和 `AXManualAccessibility` 是同一个开关，把前者设 false
  会把整棵树关掉。
- 首次真实弹窗于 12:49:49 被 AXPress 成功关闭，按钮 16×16，容器为 tooltip。

## Typeless 升级后失效怎么办

先 `hs -c 'typeless.dump()'` 看卡片出现时的树，对照 `typeless_paywall_closer.lua`
顶部 `config` 里的阈值和 `alertContainer` / `pickCloseButton` 两个函数调整。
文案变了就改 `targetTitles`。
