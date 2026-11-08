# RightClick

[![GitHub stars](https://img.shields.io/github/stars/3wlh/RightClick?style=flat-square)](https://github.com/3wlh/RightClick/stargazers)
[![GitHub release](https://img.shields.io/github/v/release/3wlh/RightClick?style=flat-square)](https://github.com/3wlh/RightClick/releases)
[![GitHub issues](https://img.shields.io/github/issues/3wlh/RightClick?style=flat-square)](https://github.com/3wlh/RightClick/issues)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg?style=flat-square)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

把常用目录、文件操作和开发工具放进 macOS Finder 右键菜单。RightClick 提供原生设置界面，支持跟随系统、浅色和深色主题。

[下载最新版本](https://github.com/3wlh/RightClick/releases/latest) · [更新说明](https://github.com/3wlh/RightClick/releases/latest)

> 当前版本：![版本](https://img.shields.io/github/v/release/3wlh/RightClick?style=flat-square&label=) 预览版，支持 macOS 14 及以上。提供 Apple Silicon 和 Intel DMG，采用 ad-hoc 签名，尚未接入 Developer ID 签名与 notarization 公证。

功能：Finder 右键菜单 · 常用目录快捷入口 · 文件剪切/粘贴/移动/复制 · 拷贝路径 · 隐藏/取消隐藏 · 直接删除 · 新建文件模板 · 开发者工具入口 · 操作历史 · 登录时自动启动 · Finder Extension 修复

---

## 功能概览

### 1. Finder 右键菜单

将高频动作放到 Finder 当前目录、选中文件/文件夹、工具栏等上下文中：

- 全局 Finder Sync 作用域，菜单不再受固定目录白名单限制；
- 菜单项按“常用目录 / 文件操作 / 新建文件 / 开发者工具”分组；
- 支持一级菜单与分组菜单两种摆放方式；
- 菜单项支持整行拖拽排序，可归入内置功能分组或自定义分组；
- 保存配置后通知 Finder Extension 刷新菜单缓存；
- Finder Extension 只负责渲染和派发，不直接修改文件。

### 2. 常用目录快捷入口

适合桌面、下载、项目目录、素材目录等高频位置：

- 快速打开指定目录；
- 将选中文件移动到指定目录；
- 将选中文件复制到指定目录；
- 支持通过设置页添加、替换、删除和排序；
- 默认目录仅初始化一次，删除后不会在下次启动时重新出现。

### 3. 文件操作

把常用文件动作放进右键菜单：

- 剪切、粘贴；
- 移动、复制；
- 拷贝路径：选中项目时拷贝其完整路径，目录空白处右键时拷贝当前目录路径；
- 隐藏文件 / 取消隐藏：切换所选项目的隐藏标记；
- 直接删除：二次确认后永久删除，不进入废纸篓；
- 批量操作保留逐项结果，部分失败后继续处理其他文件；
- 粘贴部分失败后保留未完成项，修复问题后可重试；
- 操作记录写入本地 JSONL，方便回看执行结果；
- 历史或剪切板保存失败时仍保留真实操作结果，并显示恢复指引。

当前版本尚不支持撤销文件操作。

### 4. 新建文件模板

在当前 Finder 目录快速创建起始文件：

- 内置文本、Markdown、JSON 模板；
- 支持自定义模板标题、默认文件名和内容；
- 文件冲突时默认“保留两者”，避免静默覆盖。

### 5. 开发者快捷入口

面向开发者工作流的 App 快速打开能力：

- 默认内置 Terminal 入口；
- 支持自定义 macOS App；
- 可按当前目录、选中项或动态上下文打开目标；
- 对常见开发工具优先使用其 CLI 启动方式。

### 6. 权限与修复入口

RightClick 不安装特权 Helper，也不会静默请求系统权限：

- 文件动作以当前用户身份执行；
- macOS 拒绝访问时，会提示前往 Full Disk Access；
- 不通过读取 Mail、Messages、Safari、TCC 或 Group Containers 来探测权限；
- 设置页提供 Finder Extension 注册、修复和重启 Finder 的入口。

### 7. 配置管理

- 自定义分组：新建、重命名、排序、删除，菜单项可归入分组；
- 配置导入 / 导出：导出为 JSON，导入时校验 schema 版本并刷新 Finder 菜单；
- 配置文件统一保存为 `~/Library/Application Support/com.local.rightclick/rightclick.json`，其中同时包含配置与常用目录书签，单一文件即可备份与迁移。

---

## 安装

### 选项 A：从 Releases 下载 DMG

前往 [最新 Release](https://github.com/3wlh/RightClick/releases/latest) 下载预览包，按 Mac 芯片选择：

| 设备 | 安装包 |
| --- | --- |
| Apple Silicon（M 系列） | [arm64 DMG](https://github.com/3wlh/RightClick/releases/latest/download/RightClick-arm64-preview.dmg) |
| Intel Mac | [x86_64 DMG](https://github.com/3wlh/RightClick/releases/latest/download/RightClick-x86_64-preview.dmg) |

可在“苹果菜单 > 关于本机”查看芯片或处理器类型。

1. 打开 DMG。
2. 将 `RightClick.app` 拖到 `/Applications`。
3. 从 `/Applications` 启动 `RightClick`。
4. 首次启动时，App 会自动注册随包附带的 Finder Extension，并可能重启 Finder 一次。
5. 如果系统要求手动确认，请前往“系统设置 > 通用 > 登录项与扩展 > Finder 扩展”启用 RightClick。

如果 macOS 提示应用无法打开或已损坏，可在本地测试时清理 quarantine：

```bash
xattr -cr "/Applications/RightClick.app"
```

### 选项 B：本地开发安装

```bash
scripts/package-macos.sh debug
rm -rf "/Applications/RightClick.app"
ditto "dist/staging/RightClick.app" "/Applications/RightClick.app"
xattr -cr "/Applications/RightClick.app"
open "/Applications/RightClick.app"
```

安装到 `/Applications` 后，由 App 在运行时注册内置 Finder Extension。默认不会注册 `dist/staging` 中的构建产物，避免 Finder 把源码目录里的临时 App 当作真实应用。

---

## 常见问题排查

### Finder 右键菜单没有出现？

1. 确认 App 位于 `/Applications/RightClick.app`。
2. 打开系统设置中的 Finder 扩展页，确认 RightClick Finder Extension 已启用。
3. 打开 RightClick 设置页，在概览中使用“修复并重启 Finder”。
4. 仍未出现时，可手动运行：

```bash
killall Finder
```

### macOS 提示需要完全磁盘访问权限？

文件动作由 macOS 权限系统决定是否能访问目标路径。请前往：

```text
系统设置 > 隐私与安全性 > 完全磁盘访问权限
```

允许 `RightClick` 后重试。RightClick 不会为了检测权限而主动读取其他 App 的数据目录。

### macOS 提示“想访问其他 App 的数据”？

新版运行时状态默认写入：

```text
~/Library/Application Support/com.local.rightclick
```

它不会默认读取 `~/Library/Group Containers`，也不会读取 Mail、Messages、Safari 或 TCC 数据。若你从旧版本升级后仍看到提示，请完全退出 RightClick、重启 Finder 后再安装最新包。

### 应用提示未公证或无法验证开发者？

当前预览包尚未接入 Developer ID 签名和 notarization 公证。你可以在“系统设置 > 隐私与安全性”中选择仍要打开，或在本地测试时清理 quarantine。

---

## 验证状态与当前限制

- 发布由 [GitHub Actions](https://github.com/3wlh/RightClick/actions/workflows/package-macos.yml) 手动触发：一次运行同时完成 arm64 / x86_64 打包并自动创建正式 Release。
- 测试覆盖 Core 执行逻辑和设置持久化，包括批次重试与文件操作失败回滚。
- 已安装 Finder Extension 的通知刷新、真实 XPC 故障和权限切换仍待实机验收。
- 当前不支持文件操作撤销；安装包未进行 Developer ID 签名与公证。

---

## 开发与构建

### 前置要求

- macOS 14 Sonoma 或更新版本；
- Swift 6 工具链；
- 本地打包需要系统可用的 `codesign`、`sips`、`iconutil`。

### 运行检查

```bash
scripts/ci-swift-check.sh debug
```

### 构建设置 App target

```bash
swift build --target RightClickAppPreview
```

### 构建本地预览 App bundle

```bash
scripts/package-macos.sh debug
```

### 构建本地预览 DMG

```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
```

### 发布 Release（GitHub Actions）

1. 打开仓库的 Actions 页面，选择 `Package macOS`，点击 `Run workflow`；
2. `version` 留空则使用当天日期（如 `26.11.08`），也可以填指定版本（如 `0.1.0`）；
3. 运行结束后自动创建对应的正式 Release，并把 arm64 / x86_64 的 DMG 上传为 Release 资产。

推送 `v*` tag 不再触发构建；同一版本重复运行会覆盖同名资产。

### 本地 Finder Sync smoke test

```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
```

---

## 架构

```text
Finder
  -> RightClickFinderExtension
  -> NSXPCConnection
  -> RightClickActionRunner.xpc
  -> RightClickCore
```

项目主要分为四个 target：

- `RightClickCore`：共享模型、菜单构建、存储、文件操作、操作日志和 XPC 合约。
- `RightClickFinderExtension`：读取配置并渲染 Finder 菜单，不直接修改文件。
- `RightClickActionRunnerService`：XPC 服务入口，把请求交给 Core 层 ActionRunner。
- `RightClickAppPreview`：菜单栏 App 和设置窗口。

运行时状态默认写入真实用户目录：

```text
~/Library/Application Support/com.local.rightclick
├── rightclick.json        # 配置 + 常用目录书签（唯一配置文件）
└── icon-cache/
    └── v1/
```

剪切状态保存在 ActionRunner 进程内存中，不再生成额外文件。

旧版本遗留的 `config.json` 和 `bookmarks.json` 会在启动时自动合并进 `rightclick.json` 并删除。

---

## 仓库结构

```text
Sources/
├── RightClickCore/
├── RightClickFinderExtension/
├── RightClickActionRunnerService/
└── RightClickAppPreview/
Tests/
├── RightClickCoreTests/
└── RightClickAppPreviewTests/
scripts/
├── ci-swift-check.sh
└── package-macos.sh
design/
├── icon.png
└── sidebar-icon.png
```

---

## 贡献

欢迎提交 issue 和 pull request。改动时建议遵守现有边界：

- 共享模型和执行逻辑放在 `RightClickCore`；
- Finder 菜单渲染放在 `RightClickFinderExtension`；
- 设置 UI 和 AppKit/SwiftUI 表现层放在 `RightClickAppPreview`；
- XPC service 入口保持轻量。

如果新增或修改一种 Finder action kind，通常需要同步更新模型、菜单投影、执行逻辑、设置页展示和测试。

提交前建议至少运行：

```bash
git diff --check
scripts/ci-swift-check.sh debug
```

如果改到 Finder Extension、XPC、entitlements 或打包逻辑，还需要运行：

```bash
scripts/package-macos.sh debug
```

---

## 致谢

本项目基于 [iheeleme/RightClick-Pro](https://github.com/iheeleme/RightClick-Pro) 修改而来，属于其衍生作品，并在其基础上进行了大量重构与功能扩展，感谢原作者的开源工作。

感谢[LinuxDo](https://linux.do/)社区，真诚、友善、团结、专业，共建你我引以为荣之社区。

感谢 macOS Finder Sync、SwiftUI、Swift Package Manager 生态，以及所有为开发者效率工具提供思路的开源项目。

---

## 许可证

本项目默认采用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 许可协议（署名-非商业性使用-相同方式共享）。

- 允许：个人学习、研究、非商业场景下的使用、修改与分享，需保留署名并遵循相同协议分享要求。
- 不允许：任何未获授权的商业使用，包括但不限于企业内部商业目的、对外商业服务、付费产品集成、二次分发售卖等。
- 商业授权：如需商业使用，请先联系项目维护者获取单独书面授权。

---

## 免责声明

本项目仅供个人学习、研究和非商业使用。使用本项目即表示你同意：

- 未获得维护者书面商业授权前，不将本项目用于任何商业用途；
- 自行承担安装、运行、修改和分发本项目产生的风险与责任；
- 遵守 macOS、Finder Extension、相关第三方服务条款和所在地法律法规。

项目维护者不对因使用本项目而产生的任何直接或间接损失承担责任。
