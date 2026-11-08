import Foundation

public enum FinderSyncScope {
    public static var globalRoot: URL {
        URL(fileURLWithPath: "/")
    }

    /// Finder Sync 只观察注册目录的子树，且该子树不会跨越文件系统边界。
    /// 仅注册 `/` 只覆盖启动盘，外置盘、磁盘映像和网络卷都没有右键菜单，
    /// 因此需要额外注册每个可浏览的已挂载卷根目录。
    /// 这里不能使用 `.skipHiddenVolumes`：Finder 中“隐藏”的外置盘同样是 `isHidden == true`。
    public static func syncRoots() -> [URL] {
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsBrowsableKey],
            options: []
        ) ?? []

        var roots = [globalRoot]
        var seenPaths: Set<String> = [globalRoot.path]

        for volume in mountedVolumes where volume.isFileURL {
            guard isBrowsableVolume(volume) else {
                continue
            }
            guard seenPaths.insert(volume.path).inserted else {
                continue
            }
            roots.append(volume)
        }

        return roots
    }

    private static func isBrowsableVolume(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsBrowsableKey])
        return values?.volumeIsBrowsable == true
    }

    public static func contextIsInGlobalScope(_ context: FinderContext) -> Bool {
        true
    }
}
