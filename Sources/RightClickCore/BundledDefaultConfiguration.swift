import Foundation

extension DefaultConfiguration {
    /// 编译进二进制的默认配置。
    ///
    /// 内容就是可直接编辑的 JSON（使用原始字符串，`\n` 保持为 JSON 转义而不是 Swift 转义）。
    /// 修改后重新编译即可生效，无需随 App 分发额外资源文件。
    static let embeddedJSON = #"""
    {
      "maxRootMenuActions": 5,
      "submenuGroupOrder": [
        "commonDirectories",
        "moveToCommonDirectory",
        "copyToCommonDirectory",
        "createFile",
        "developerEntrypoints",
        "developerTools",
        "fileOperations",
        "commandTemplates"
      ],
      "directories": [
        { "id": "desktop", "title": "桌面", "path": "~/Desktop", "isEnabled": false },
        { "id": "downloads", "title": "下载", "path": "~/Downloads", "isEnabled": false }
      ],
      "fileOperationActions": [
        { "id": "copy-path", "title": "拷贝路径", "kind": "copyPath", "visibility": ["selection", "container"], "isEnabled": true },
        { "id": "paste-here", "title": "粘贴到此处", "kind": "paste", "visibility": ["container", "selection"], "isEnabled": true },
        { "id": "cut-selection", "title": "剪切", "kind": "cut", "visibility": ["selection"], "isEnabled": true },
        { "id": "hide-selection", "title": "隐藏文件", "kind": "hideItems", "visibility": ["selection"], "isEnabled": true },
        { "id": "unhide-selection", "title": "取消隐藏", "kind": "unhideItems", "visibility": ["selection"], "isEnabled": true },
        { "id": "delete-permanently", "title": "直接删除", "kind": "deletePermanently", "visibility": ["selection"], "isEnabled": true },
        { "id": "airdrop-share", "title": "AirDrop 发送", "kind": "airDrop", "visibility": ["selection"], "isEnabled": false }
      ],
      "fileTemplates": [
        { "id": "template-txt", "title": "空白文本", "defaultFileName": "未命名.txt", "contents": "", "isEnabled": true },
        { "id": "template-md", "title": "Markdown", "defaultFileName": "未命名.md", "contents": "# Untitled\n", "isEnabled": true },
        { "id": "template-json", "title": "JSON", "defaultFileName": "未命名.json", "contents": "{\n  \n}\n", "isEnabled": true }
      ],
      "developerEntrypoints": [
        {
          "id": "developer-terminal",
          "title": "在 Terminal 打开",
          "bundleIdentifier": "com.apple.Terminal",
          "targetMode": "dynamic",
          "applicationDirectory": "/System/Applications/Utilities",
          "isEnabled": true
        }
      ],
      "commandTemplates": [
        {
          "id": "command-clear-quarantine",
          "title": "清除隔离属性",
          "command": "xattr -dr com.apple.quarantine {{selectedPaths}}",
          "workingDirectory": "currentDirectory",
          "timeoutSeconds": 60,
          "runInTerminal": true,
          "iconSymbol": "terminal",
          "isEnabled": false
        }
      ]
    }
    """#

    /// 当前生效的默认配置：解析编译进二进制的 JSON，失败时退回 `fallback`。
    static let bundled: DefaultConfiguration = {
        do {
            return try JSONDecoder().decode(
                DefaultConfiguration.self,
                from: Data(embeddedJSON.utf8)
            )
        } catch {
            NSLog("RightClick: 内置默认配置解析失败，已改用代码默认值：\(error)")
            return fallback
        }
    }()
}
