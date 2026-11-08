import XCTest
@testable import RightClickCore

final class MenuBuilderTests: XCTestCase {
    func testExternalResourceIconsExposeLightweightFallbacks() {
        XCTAssertTrue(MenuIconDescriptor.appBundleIdentifier("com.apple.Terminal").requiresExternalResourceLookup)
        XCTAssertEqual(
            MenuIconDescriptor.appBundleIdentifier("com.apple.Terminal").lightweightFallback,
            .systemSymbol("app")
        )

        XCTAssertTrue(MenuIconDescriptor.filePath("/Users/test/Downloads").requiresExternalResourceLookup)
        XCTAssertEqual(
            MenuIconDescriptor.filePath("/Users/test/Downloads").lightweightFallback,
            .folder
        )
        XCTAssertEqual(
            MenuIconDescriptor.filePath("/Users/test/Notes/today.md").lightweightFallback,
            .fileExtension("md")
        )
    }

    func testIntrinsicIconsDoNotRequireExternalResourceLookup() {
        let icons: [MenuIconDescriptor] = [
            .systemSymbol("terminal"),
            .fileExtension("swift"),
            .folder
        ]

        for icon in icons {
            XCTAssertFalse(icon.requiresExternalResourceLookup)
            XCTAssertEqual(icon.lightweightFallback, icon)
        }
    }

    func testRootMenuItemsAreLimitedToConfiguredMaximum() {
        let actions = (0..<7).map { index in
            RightClickAction(
                id: "root-\(index)",
                title: "Root \(index)",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                order: index
            )
        }
        let config = RightClickConfig(maxRootMenuActions: 5, actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["root-0", "root-1", "root-2", "root-3", "root-4"])
    }

    func testMenuFiltersByFinderInvocation() {
        let actions = [
            RightClickAction(
                id: "selection",
                title: "Selection",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightClickAction(
                id: "container",
                title: "Container",
                kind: .paste,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 2
            )
        ]
        let config = RightClickConfig(actions: actions)
        let context = FinderContext(invocation: .selection, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.groupedSubmenuItems[.fileOperations]?.map(\.id), ["selection"])
    }

    func testMenuAssignsDeveloperAppIcon() {
        let entrypoint = DeveloperEntrypoint(
            id: "cursor",
            title: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92"
        )
        let action = RightClickAction(
            id: "open-cursor",
            title: "Open Cursor",
            kind: .openInApp,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(developerEntrypointID: entrypoint.id)
        )
        let config = RightClickConfig(actions: [action], developerEntrypoints: [entrypoint])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .appBundleIdentifier(entrypoint.bundleIdentifier))
    }

    func testMenuAssignsTemplateFileTypeIcon() {
        let template = FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Note.md")
        let action = RightClickAction(
            id: "new-markdown",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(templateID: template.id)
        )
        let config = RightClickConfig(actions: [action], fileTemplates: [template])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .fileExtension("md"))
    }

    func testMenuAssignsDirectoryPathIcon() {
        let bookmark = DirectoryBookmark(id: "code", displayName: "Code", path: "/Users/test/Code")
        let action = RightClickAction(
            id: "open-code",
            title: "Open Code",
            kind: .openDirectory,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(directoryID: bookmark.id)
        )
        let config = RightClickConfig(actions: [action])
        let bookmarks = DirectoryBookmarkCatalog(bookmarks: [bookmark])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context, bookmarks: bookmarks)

        XCTAssertEqual(menu.rootItems.first?.icon, .filePath(bookmark.path))
    }

    func testRootItemStaysRootWhenMatchingSubmenuGroupExists() {
        let actions = [
            RightClickAction(
                id: "new-markdown",
                title: "新建 Markdown",
                kind: .createFile,
                visibility: [.container],
                placement: .rootMenu,
                group: .createFile,
                order: 20,
                payload: ActionPayload(templateID: "template-md")
            ),
            RightClickAction(
                id: "new-json",
                title: "新建 JSON",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 30,
                payload: ActionPayload(templateID: "template-json")
            )
        ]
        let config = RightClickConfig(actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["new-markdown"])
        XCTAssertEqual(menu.groupedSubmenuItems[.createFile]?.map(\.id), ["new-json"])
    }

    func testMenuAssignsFileOperationIcons() {
        let actions = [
            RightClickAction(
                id: "copy-path",
                title: "拷贝路径",
                kind: .copyPath,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightClickAction(
                id: "hide-selection",
                title: "隐藏文件",
                kind: .hideItems,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 2
            ),
            RightClickAction(
                id: "unhide-selection",
                title: "取消隐藏",
                kind: .unhideItems,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 3
            ),
            RightClickAction(
                id: "delete-permanently",
                title: "直接删除",
                kind: .deletePermanently,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 4
            )
        ]
        let config = RightClickConfig(actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(
            menu.groupedSubmenuItems[.fileOperations]?.map(\.icon),
            [
                .systemSymbol("link"),
                .systemSymbol("eye.slash"),
                .systemSymbol("eye"),
                .systemSymbol("trash.slash")
            ]
        )
    }
}
