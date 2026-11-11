# 项目速览

## 是什么

RightClick 是一个 macOS Finder 右键菜单增强工具。核心链路：

```
rightclick.json ──(ConfigurationBootstrapper)──▶ RightClickConfig
                                                    │
                                                    ▼
Finder 右键菜单 ──▶ FinderSyncController ──▶ MenuBuilder ──▶ 菜单项
    │
    ├──▶ ActionRunner（进程内操作：拷贝、剪切、隐藏、删除）
    ├──▶ URL Scheme（rightclick://run-command / rightclick://airdrop）
    │       └──▶ 主 App 处理：Apple Events 控制 Terminal、NSSharingService AirDrop
    └──▶ 主 App 设置窗口（手动编辑配置，保存后 DistributedNotification 通知 Finder 重载）
```

## 模块

| Target | 职责 |
|---|---|
| `RightClickCore` | 纯模型层：ActionModels、MenuBuilder、ConfigurationBootstrapper、存储、App 定位、Finder 上下文。**无 AppKit/UIKit 依赖**，Finder 扩展和主 App 都依赖它 |
| `RightClickFinderExtension` | Finder Sync Extension（沙盒内，只读 `rightclick.json`）：展示菜单、转发动作。删文件、切路径等文件操作**在扩展内**完成 |
| `RightClickAppPreview` | SwiftUI 设置窗口（主 App，**取消沙盒**以读用户文件）：编辑配置、管理书签、预览菜单、命令模板编辑器 |
| `RightClickActionRunnerService` | XPC 服务，Finder 扩展可用它执行需要高权限的动作 |

## 核心文件

| 文件 | 说明 |
|---|---|
| `Sources/RightClickCore/ActionModels.swift` | **核心模型**：`RightClickConfig`、`RightClickAction`、`ActionKind`、`MenuGroup`、`CommandTemplate`、`DirectoryBookmark` |
| `Sources/RightClickCore/BundledDefaultConfiguration.swift` | 内嵌默认配置（编译进二进制的 JSON 字符串），首次安装和恢复默认的唯一数据源 |
| `Sources/RightClickCore/DefaultConfiguration.swift` | 默认配置的解码类型定义 + `fallback`（解析失败时的代码兜底） |
| `Sources/RightClickCore/ConfigurationBootstrapper.swift` | 首次安装生成配置、旧配置迁移修复 |
| `Sources/RightClickCore/MenuBuilder.swift` | 把 `RightClickConfig` + Finder 上下文 转成最终菜单项 |
| `Sources/RightClickFinderExtension/FinderSyncController.swift` | Finder 扩展主入口：读配置、构建菜单、执行动作 |
| `Sources/RightClickAppPreview/SettingsViewModel.swift` | 设置窗口的状态管理：配置读写、书签编辑、脏标记、保存 |

## 配置文件

- 路径：`~/Library/Application Support/com.local.rightclick/rightclick.json`
- 单文件格式：同时包含 `config`（菜单项/模板/命令模板）和 `bookmarks`（常用目录 security-scoped bookmark）
- Schema 版本：`RightClickConstants.currentSchemaVersion = 8`
- **不存在时**才用内嵌默认配置生成；**存在时完全信任文件**，不再自动补齐

---

# 开发流程

## 保存策略

- **统一手动保存**：所有 UI 控件（开关、表单、列表编辑、拖排序）只改内存里的 `config`，设脏标记，**绝不自动落盘**。
- **唯一落盘入口**：用户点「保存配置」按钮才调 `SettingsViewModel.saveConfig()`，负责写文件 + 清脏标记 + 发 DistributedNotification 让 Finder 扩展刷新。
- **智能脏标记**：所有 setter 统一调 `SettingsViewModel.markUnsaved()`（`internal`），内部做 `config != savedConfig || bookmarks != savedBookmarks` 比较——值没变就清脏，避免开关开→关→开回到原值还显示保存按钮。
- **禁止直接赋值**：任何视图层代码都不要写 `viewModel.hasUnsavedChanges = true`，必须走 `markUnsaved()`。

## 默认配置

- **单一数据源**：所有首次安装/恢复默认的内容集中在 `BundledDefaultConfiguration.swift` 的 `embeddedJSON` 里（原始字符串内嵌 JSON，编译进二进制，不依赖外部资源文件）。
- **字段覆盖范围**：`directories`（常用目录，支持 `~` 展开）、`fileOperationActions`（文件操作菜单项）、`fileTemplates`（新建文件模板）、`developerEntrypoints`（应用入口）、`commandTemplates`（命令模板）。每项可配 `isEnabled` 控制默认启用状态。
- **运行时生成**：目录会展开书签、生成 3 个动作（打开 / 移动到 / 拷贝到）；书签动作的 `order` 由代码按数组顺序递增分配——这些动态逻辑留在 `ConfigurationBootstrapper` 里，JSON 只声明静态部分。
- **生效时机**：只有 `rightclick.json` **不存在**时才用内嵌 JSON 生成；配置文件一旦存在，完全以文件为准。
- **恢复默认**：设置概览页底部有「恢复默认配置」按钮（橙色循环图标），点后弹二次确认，确认才调用 `resetToDefaults()` 重写配置文件。

## Finder 扩展行为

- Finder 扩展读配置走 DistributedNotification + 重新加载 `rightclick.json`，不与主 App 共享内存状态。
- **直接删除**（`deletePermanently`）动作受 `config.confirmBeforeDelete` 控制：
  - `true`（默认）：Finder 扩展弹 `NSAlert` 二次确认
  - `false`：静默 `FileManager.default.removeItem`，不进废纸篓
- 这个开关是**全局配置**，不是单个菜单项属性——因为 Finder 扩展对"是否弹确认"没有上下文区分能力。

## 沙盒状态

- **主 App**：已取消 App Sandbox（`package-macos.sh` 里 entitlements 不含 `com.apple.security.app-sandbox`），因为需要读取用户文件。保留 `com.apple.security.automation.apple-events` + Terminal 例外（命令模板控制 Terminal）。
- **Finder 扩展**：仍是沙盒进程，只读 `rightclick.json` 和沙盒内文件。

## 构建与安装

- 本地构建：`swift build`
- 打包：`bash scripts/package-macos.sh release`（产物在 `dist/staging/RightClick.app`，已做代码签名）
- 安装：`ditto dist/staging/RightClick.app /Applications/RightClick.app`，然后 `open /Applications/RightClick.app` 启动
- Finder 扩展刷新：`pluginkit -e use -i com.local.rightclick.FinderExtension && killall Finder`
- 本机只有 CommandLineTools 无 Xcode，`swift test` 不可用；测试靠 CI 跑

## 提交规则

- 每个功能/修复单独 commit，信息清晰描述"做了什么 + 为什么"。
- 推送前先 `git status` 确认没有误带临时文件，`rm -f .git/index.lock` 防止 0 字节锁文件残留。
- 打包脚本、Finder 扩展、主 App 签名三件套要一起验证，不能只看 `swift build` 通过。

## 常见坑

- 命令模板通过 URL Scheme `rightclick://run-command` 从 Finder 扩展转发到主 App 执行——扩展是沙盒进程，Apple Events 控制 Terminal 必须由主 App（已取消沙盒）完成。
- AirDrop 面板不弹出 = 主 App 沙盒内读不到目标文件。这是之前取消沙盒的直接原因。
- 目录 `id` 改了等于新增一项（动作 id 由它派生），旧的不会自动清理。
