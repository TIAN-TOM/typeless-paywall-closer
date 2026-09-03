# typeless-paywall-closer

Hammerspoon 脚本，自动关闭 Typeless（macOS，Electron）悬浮条里的两种付费提示卡片：
**"Upgrade for enhanced accuracy"** 和 **"High demand"**。只处理这两条，不碰其他通知。

不改 Typeless 本体，不碰网络流量，Typeless 升级后只要卡片结构不变就继续工作。
代价是卡片会闪一下再消失，通常不到 0.2 秒。

## 文件

| 文件 | 作用 |
|---|---|
| `typeless_paywall_closer.lua` | 全部逻辑。`~/.hammerspoon/typeless_paywall_closer.lua` 是指向它的符号链接，改完直接 `hs.reload()` 生效 |
| `install.sh` | 一键安装、更新、卸载 |
| `init.lua.example` | `~/.hammerspoon/init.lua` 的参考内容 |
| `tools/asar_scan.js` | 不解包直接在 Typeless 的 `app.asar` 里搜字符串并打印上下文 |
| `tools/asar_extract.js` | 把 `app.asar` 的 `dist/` 解到当前目录的 `typeless_dist/` |
| `tools/cgwin.swift` | 用 CGWindowList 列出 Typeless 的所有窗口，不需要辅助功能权限 |
| `docs/retrospective.md` | 排查与实现复盘 |

运行时日志写在 `~/Library/Logs/typeless-paywall-closer/activity.log`，只记关闭、警告、启动和权限变化。

## 安装

一键方式，需要先装好 [Homebrew](https://brew.sh)：

```bash
git clone https://github.com/TIAN-TOM/typeless-paywall-closer.git && cd typeless-paywall-closer && ./install.sh
```

脚本会装 Hammerspoon、建符号链接、往 `~/.hammerspoon/init.lua` 追加启动代码，然后打开辅助功能设置页。
之后按提示做三件事：Gatekeeper 询问时点"打开"，在辅助功能里打开 Hammerspoon，退出并重开一次 Hammerspoon。
以后更新只需 `git pull` 再跑一次 `./install.sh`。卸载用 `./install.sh uninstall`，Hammerspoon 本身会保留。

手动方式：

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

## 菜单栏

菜单栏会出现一个 `⌧` 图标：

- Enabled / Paused 开关。暂停后不再扫描，进程仍保持挂载。
- 辅助功能权限状态、Typeless 是否已挂载、当前扫描档位、最近一次关闭的时间和本次会话关闭次数。
- Scan now、Dump AX tree to console、Open log file、Reload Hammerspoon。

## 隐私

脚本需要辅助功能权限，这个权限允许它读取任何应用的界面。它实际只读 Typeless 悬浮条窗口里的文字，
用来和两条目标标题比较，比较完即丢弃。听写过程中悬浮条可能显示实时转写，这些文字不会被记录、
写入日志或发到任何地方。日志里只出现匹配到的标题、按钮坐标和时间。脚本不联网，不改任何文件。

## 调试

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

快捷键 `⌃⌥⌘T`（Control+Option+Command+T）会打开控制台并 dump 一次。成功关闭时日志里会有一行
`closed "…" via AXPress`。`selfTest()` 用假数据跑匹配规则和调度逻辑，启动时也会自动跑一遍，
失败会写进日志。

## 工作原理

1. 用 Bundle ID `now.typeless.desktop` 找到进程，对 application 元素设
   `AXManualAccessibility = true`，否则 Chromium 不暴露网页内容的 AX 树。所有 AX 查询设 1 秒超时，
   Typeless 卡死不会拖住 Hammerspoon。
2. 轮询触发。Chromium 不会为内容变化发 AX 通知，注册了 90 种一条都收不到。扫描节奏跟着麦克风走：
   任一输入设备在用时，以及停用后的 10 秒内，每 0.15 秒扫一次；其余时间每 2 秒扫一次兜底。
   付费卡片只会随一次听写的响应到达，所以空闲时不值得高频扫。
3. 只扫宽度不超过 900px 的窗口。悬浮条窗口标题是 "Status"，750×500，空闲时只有十几个节点。
   设置主窗口至少 988 宽，会被跳过。
4. 找到 `AXStaticText` 的值等于目标标题后，向上找到 `AXSubrole == AXUserInterfaceTooltip`
   的容器（对应 HTML `role="tooltip"`），只在容器内找按钮。
5. 候选按钮必须同时满足：`actionNames` 里有 `AXPress`、无名或名为 close / dismiss / x / ×、
   边长不超过 40px。多个候选取最靠容器右上角的那个。带文字的按钮如 "Upgrade" 永远不会被点。
   默认不做鼠标模拟；`clickFallback = true` 可以在 AXPress 被拒绝时退化为模拟点击。

可调参数都在 `typeless_paywall_closer.lua` 顶部的 `config` 表里，也可以运行时改 `typeless.config`。

## 已验证的事实（Typeless 2.5.0，2026-09-03）

- 弹窗文案不在本地包里。服务端在 `/ai/voice_flow` 返回里带 `important_notification`，
  结构是 `{type: "paywall", display: {title, description, icon}, behavior, actions}`，
  `icon` 只有 `diamond`（Upgrade for enhanced accuracy）和 `sandglass`（High demand）两种。
  客户端标记为 `paywall`，交给悬浮条渲染。在本地包里搜文案替换没有用；把处理 `paywall` 的两处调用打成空操作可以
  （typeless-toolkit 就是这么做的），但要改 `app.asar`、处理完整性校验、在 macOS 上重签名，每次官方更新后重打。本项目不走这条路。
- 卡片组件是 MUI Tooltip，`closable` 时右上角挂一个 `IconButton`，内含 16px `CloseIcon`，
  没有 `aria-label`。两种卡片结构相同。
- `AXEnhancedUserInterface` 和 `AXManualAccessibility` 是同一个开关，把前者设 false
  会把整棵树关掉。
- 真实弹窗多次被 AXPress 成功关闭，按钮 16×16，容器为 tooltip，从未触发过鼠标模拟。
- `targetTitles` 另含 2.4.0 时期的 `Get unlimited words` / `获取无限字数`，来自 typeless-plusplus 的记录，本机未见过。
  精确匹配整段标题，所以就算永远不出现也无害。

## 同类项目

| 项目 | 思路 | 平台 | 取舍 |
|---|---|---|---|
| [JeasonKim/typeless-paywall-gateway](https://github.com/JeasonKim/typeless-paywall-gateway) | 用隐藏设置 `__DEV_API_HOST` 把 API 指到本地代理，改写返回里的 `paywall` 通知 | macOS、Windows | 卡片完全不出现，不需要辅助功能权限；但全部语音和转写流量经过本地代理，依赖一个官方随时可能删掉的隐藏开关，安装要 Node 和 pnpm |
| [Ayndpa/typeless-popup-remover](https://github.com/Ayndpa/typeless-popup-remover) | 改 `app.asar` 让弹窗渲染函数直接 return，并关掉 Electron 完整性校验 | Windows | 卡片完全不出现；但修改了应用本体，每次升级都要重打补丁 |
| [timmyagentic/typeless-plusplus](https://github.com/timmyagentic/typeless-plusplus) | 原生 Swift 菜单栏 App，同样走辅助功能树点 ×，另做账号管理和额度守护 | macOS | 开源、MIT、有公证；但源码没有设置 `AXManualAccessibility`，作者自述真实弹窗尚未验证 |
| [Jia131313/typeless-toolkit](https://github.com/Jia131313/typeless-toolkit) | 扫描 `app.asar`，把处理 `paywall` 的两处调用等长替换成空操作，同步完整性校验并重签名 | macOS、Windows | 生态里 star 最多，功能是多账号、词库同步、设备重置的超集；卡片完全不出现，但修改应用本体，每次官方更新后要重打 |
| [liuxiaoyu-fiveleven/Typeless-AD-Skipper](https://github.com/liuxiaoyu-fiveleven/Typeless-AD-Skipper) | 辅助功能树里找卡片点 ×，和本项目同路 | macOS | 闭源，ad-hoc 签名未公证，二进制带反调试 |

本项目选择"渲染后立即关掉"这条路，不改包、不拦流量，信任面最小，代价是卡片会闪一下。如果闪动不可接受，gateway 和 toolkit 是能做到不出现的开源方案，前者经过本地代理，后者修改应用本体。

## Typeless 升级后失效怎么办

先 `hs -c 'typeless.dump()'` 看卡片出现时的树，对照 `typeless_paywall_closer.lua`
顶部 `config` 里的阈值和 `alertContainer` / `M.matcher.chooseCloseButton` 两个函数调整。
文案变了就改 `targetTitles`，改完跑一遍 `selfTest()`。付费文案由服务端按账号语言下发，
把 Typeless 切成其他界面语言后标题可能变化，需要在 `targetTitles` 里补对应语言的标题。

## License

MIT
