# LG Controller（LG 遥控器）— macOS 状态栏 App：用 Mac 音量键控制 LG webOS TV 音量

[English README](README.md)

一个原生 macOS 状态栏 App 与配套 CLI：当 LG webOS TV 是 Mac 的当前声音输出设备时，它将 macOS 媒体音量键路由到这台电视——音量键永远调节你正在听到的声音。

> **v0.3.0 发布状态：**以 [MIT License](LICENSE) 公开发布**源码**。请从 tag 对应源码在本地自行编译；不会提供预编译 App/CLI，也没有 Developer ID 签名或 Apple notarization。App 原名 **LG Volume Router**（repo `lg-webos-volume-router` / `macos-lg-tv-volume`）；v0.2.0 起路由判据改为「声音输出设备匹配」——升级用户需在 **Set up TV… / 设置电视…** 中重新选择一次电视（见 [Changelog](CHANGELOG.md)）。

## 功能

- **按声音输出路由：**仅当 macOS 默认声音输出是已配置的 LG webOS TV 音频设备时，才路由音量加、音量减与静音键——音量键永远调节你正在听到的设备。AirPlay 输出始终放行，因为 macOS 本就能直接调节它。
- **手动 override：**三种模式——**当电视是声音输出时**（默认）、**始终路由到电视**、**从不路由到电视**。
- **保留 macOS 原有行为：**关闭路由、没有 Accessibility 权限、声音输出不是已配置的 TV 或未配置 TV 时，不拦截媒体键，macOS 继续正常处理。
- **本地 webOS 控制：**通过局域网 WSS 上的 webOS Secure Simple Access Protocol（SSAP）完成配对、状态读取、音量控制与静音。
- **极简状态栏界面：**一个开关、两步设置窗口；状态栏图标显示最近一次读到的 TV 音频状态。
- **孩子都能用，中英双语：**所有界面都是英文 + 中文并排；设置就两步「选电视、点测试」，不常用的都收进 Advanced。
- **只读连接测试：**`Test connection` 仅读取 TV 音频状态，不会修改音量或静音。
- **独立 CLI：**提供 `pair`、`status`、`up`、`down`、`mute`，不需要 macOS Accessibility 权限。
- **共用本地配对：**App 和 CLI 使用相同的配置域与 macOS Keychain service，可以共用已授权的 TV 配对信息。

本项目与 LG Electronics 没有隶属、背书或赞助关系。

## 系统要求

- macOS 13 或更高版本。
- Mac 与 LG webOS TV 位于可互相访问的本地网络。
- 用于编译源码的 Xcode command-line tools。
- 只有状态栏 App 在监听并按条件拦截全局媒体键时需要 macOS **Accessibility** 权限；CLI 不需要。

## 从源码构建

克隆仓库并构建 App 与 CLI：

```sh
git clone https://github.com/mfang0126/lg-controller.git
cd lg-controller
make all
```

源码构建会刻意关闭 code signing，输出为：

```text
build/Build/Products/Release/LGVolumeRouter.app
build/lg-volume
```

构建后启动 App：

```sh
make run-app
```

产物只是你的本地构建，并非经过 notarization 的消费者发行包。macOS 可能要求你自行决定是否信任后才能打开；请不要把该本地产物作为官方已签名版本再分发。

## 配置 App

1. 启动 App——菜单栏里显示为 **LG Controller**。
2. 点击状态栏图标，选择 **Set up TV… / 设置电视…**。
3. **你的 LG webOS 电视：**从声音输出列表里选你的电视（默认已选中当前声音输出）。
4. **电视地址 + Test 并排：**输入地址，点 **Test / 测试**。若电视提示配对，请在电视上批准。测试只读取音频状态，不会改动声音。
5. 在菜单中打开 **Control TV volume / 控制电视音量**。
6. macOS 提示时授予一次 Accessibility 权限并重启 App。该授权完全由 macOS 管理，App 不能授予、绕过或自动完成它。

不常改的东西——何时控制电视（Auto/Always/Never）、协议、端口、**取消配对**——都收在 **Advanced / 高级设置** 里。

App 会将非秘密的 TV endpoint/音频设备选择保存在本机 UserDefaults，将 webOS client key 保存在 macOS Keychain。两者都不应导出、提交到仓库或分享。

### 状态栏图标

图标表达的是**最近一次读取的 TV 音频状态**，不是路由开关状态：

| TV 状态 | 图标 |
|---|---|
| 尚未读取 | `speaker` |
| 静音 | `speaker.slash` |
| 低音量 | `speaker.wave.1` |
| 中音量 | `speaker.wave.2` |
| 高音量 | `speaker.wave.3` |

路由是否启用由 **Volume routing** 开关和图标 tooltip 表示。音频状态仅在启动、打开菜单、点击 **Test connection**、成功路由音量命令后刷新；不会持续轮询，也不会订阅电视遥控器改变的音量。

## CLI

只构建 CLI：

```sh
make cli
```

用法：

```text
./build/lg-volume <pair|status|up|down|mute> [--host <address>] [--port <port>]
```

### 配对和控制

`pair` 会先删除所选 host 已保存的 client key，再请求电视重新批准配对：

```sh
./build/lg-volume pair --host <TV_ADDRESS>
```

在电视批准后，可控制同一台 TV：

```sh
./build/lg-volume status --host <TV_ADDRESS>
./build/lg-volume up --host <TV_ADDRESS>
./build/lg-volume down --host <TV_ADDRESS>
./build/lg-volume mute --host <TV_ADDRESS>
```

如果 App 已经保存 endpoint，CLI 会读取同一份配置。`--host` 和 `--port` 是**单次命令覆盖**，不会写入配置。只使用 CLI、且没有先在 App 中配置时，每一条命令都需要带 `--host`。App 的 **Advanced settings** 提供默认的 `wss` 与 `ws` 两种 protocol；CLI **只支持 WSS**，若需要 App 与 CLI 共用 endpoint，请让 App 保持在 `wss`。

`status` 读取并输出音量/静音状态；`up`、`down` 调整音量；`mute` 会先读取当前静音状态后切换。配对 client key 始终保留在本机 Keychain，不会打印出来。

## 安全与隐私边界

- 控制请求只发送到你配置的本地 TV endpoint。
- 多数 LG TV 的局域网 WSS 使用自签名证书。源码中的例外只针对当前配置的 TV socket，不是任意 HTTPS/WSS 的通用证书绕过。
- 本项目没有账号系统、云服务、遥测、分析或远程控制中继。
- 不要在 issue、commit、截图或 release asset 中暴露 TV 地址、配对 key、Keychain export、签名证书、provisioning profile、API key 或本机构建产物。
- 本次源码发布不包含 Developer ID 证书、notarization 凭据或预编译二进制。

完整模型请参见 [Security and privacy](docs/SECURITY.md)。

## 文档

- [English README](README.md)
- [Architecture](docs/ARCHITECTURE.md) — 组件、命令流与关键不变量。
- [Security and privacy](docs/SECURITY.md) — Keychain、配对、WSS trust scope 与系统权限边界。
- [Release guide](docs/RELEASE.md) — source-only 策略与公开发布检查。
- [Contributing](CONTRIBUTING.md) — 开发与验证约定。
- [Changelog](CHANGELOG.md) — 发布历史。

## 许可

[MIT](LICENSE) © 2026 `mfang0126`。
