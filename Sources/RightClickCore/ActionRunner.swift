import Foundation

public enum ActionRunnerError: Error, Equatable, LocalizedError {
    case actionNotFound(String)
    case unsupportedAction(ActionKind)
    case missingPayload(String)
    case directoryNotFound(String)
    case templateNotFound(String)
    case developerEntrypointNotFound(String)
    case emptyClipboard

    public var errorDescription: String? {
        switch self {
        case .actionNotFound(let id):
            return "找不到动作：\(id)"
        case .unsupportedAction(let kind):
            return "暂不支持动作：\(kind.rawValue)"
        case .missingPayload(let field):
            return "动作缺少参数：\(field)"
        case .directoryNotFound(let id):
            return "找不到目录：\(id)"
        case .templateNotFound(let id):
            return "找不到模板：\(id)"
        case .developerEntrypointNotFound(let id):
            return "找不到开发者入口：\(id)"
        case .emptyClipboard:
            return "RightClick 剪切板为空"
        }
    }
}

public final class ActionRunner {
    private let configProvider: RightClickConfigProviding
    private let fileService: FileOperationService
    private let cutClipboard: CutClipboardStoring
    private let pathClipboard: PathClipboardWriting
    private let urlOpener: URLOpening
    private let developerAppOpener: DeveloperAppOpening
    private let bookmarkResolver: BookmarkResolving

    public init(
        configProvider: RightClickConfigProviding,
        fileService: FileOperationService = FileOperationService(),
        cutClipboard: CutClipboardStoring,
        pathClipboard: PathClipboardWriting = InMemoryPathClipboard(),
        urlOpener: URLOpening,
        developerAppOpener: DeveloperAppOpening,
        bookmarkResolver: BookmarkResolving = SecurityScopedBookmarkResolver()
    ) {
        self.configProvider = configProvider
        self.fileService = fileService
        self.cutClipboard = cutClipboard
        self.pathClipboard = pathClipboard
        self.urlOpener = urlOpener
        self.developerAppOpener = developerAppOpener
        self.bookmarkResolver = bookmarkResolver
    }

    public func run(_ request: ActionRequest) -> ActionResult {
        do {
            let config = try configProvider.loadConfig()
            guard let action = config.actions.first(where: { $0.id == request.actionID }) else {
                throw ActionRunnerError.actionNotFound(request.actionID)
            }
            let bookmarks = try configProvider.loadBookmarkCatalog()

            let bookmarkAccess = try AuthorizedBookmarkAccess(
                catalog: bookmarks,
                ids: try bookmarkIDs(for: action),
                resolver: bookmarkResolver
            )
            return try execute(
                action,
                config: config,
                bookmarkAccess: bookmarkAccess,
                request: request
            )
        } catch {
            let status: ActionResultStatus = (error as? FileOperationError) == .cancelled ? .cancelled : .failure
            return ActionResult(
                requestID: request.id,
                status: status,
                message: FullDiskAccessAdvisor.userFacingMessage(for: error)
            )
        }
    }

    private func bookmarkIDs(for action: RightClickAction) throws -> [String] {
        switch action.kind {
        case .openDirectory, .moveToDirectory, .copyToDirectory:
            guard let directoryID = action.payload.directoryID else {
                throw ActionRunnerError.missingPayload("directoryID")
            }
            return [directoryID]
        case .cut, .paste, .createFile, .openInApp, .copyPath, .hideItems, .unhideItems, .deletePermanently, .undoOperation, .airDrop, .runCommand:
            return []
        }
    }

    private func execute(
        _ action: RightClickAction,
        config: RightClickConfig,
        bookmarkAccess: AuthorizedBookmarkAccess,
        request: ActionRequest
    ) throws -> ActionResult {
        switch action.kind {
        case .openDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            try urlOpener.open(directory)
            return ActionResult(requestID: request.id, status: .success, message: "已打开目录", affectedURLs: [directory])

        case .moveToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            let batch = try fileService.moveBatch(request.context.selectedItems, to: directory)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "移动完成",
                failurePrefix: "移动未完全完成"
            )

        case .copyToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            let batch = try fileService.copyBatch(request.context.selectedItems, to: directory)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "复制完成",
                failurePrefix: "复制未完全完成"
            )

        case .cut:
            guard !request.context.selectedItems.isEmpty else {
                throw FileOperationError.missingSelection
            }
            try cutClipboard.save(CutClipboardRecord(sourceURLs: request.context.selectedItems))
            return ActionResult(requestID: request.id, status: .success, message: "已记录剪切项目", affectedURLs: request.context.selectedItems)

        case .paste:
            guard let record = try cutClipboard.load(), !record.sourceURLs.isEmpty else {
                throw ActionRunnerError.emptyClipboard
            }
            let batch = try fileService.moveBatch(record.sourceURLs, to: pasteDestination(for: request.context))
            var result = actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "粘贴完成",
                failurePrefix: "粘贴未完全完成"
            )
            do {
                if batch.remainingSourceURLs.isEmpty {
                    try cutClipboard.clear()
                } else {
                    // 只保留待处理项，再次粘贴不会重复移动已完成项目。
                    try cutClipboard.save(CutClipboardRecord(sourceURLs: batch.remainingSourceURLs))
                }
            } catch {
                result.status = .failure
                result.message += "\n剪切板更新失败：\(error.localizedDescription)。再次粘贴前，请重新剪切需要操作的文件。"
            }
            return result

        case .createFile:
            let template = try fileTemplate(from: action, config: config)
            let outcome = try fileService.createFile(template: template, in: request.context.targetDirectory)
            return ActionResult(requestID: request.id, status: .success, message: "文件已创建", affectedURLs: [outcome.destinationURL])

        case .openInApp:
            let entrypoint = try developerEntrypoint(from: action, config: config)
            let targetURL = developerTargetURL(for: entrypoint, context: request.context)
            try developerAppOpener.open(entrypoint, targetURL: targetURL)
            return ActionResult(requestID: request.id, status: .success, message: "已打开开发者入口", affectedURLs: [targetURL])

        case .copyPath:
            let urls = request.context.selectedItems.isEmpty
                ? [request.context.targetDirectory]
                : request.context.selectedItems
            try pathClipboard.writePaths(urls.map(\.path))
            return ActionResult(requestID: request.id, status: .success, message: "路径已拷贝", affectedURLs: urls)

        case .hideItems:
            let batch = try fileService.setHiddenBatch(request.context.selectedItems, hidden: true)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "已隐藏文件",
                failurePrefix: "隐藏未完全完成"
            )

        case .unhideItems:
            let batch = try fileService.setHiddenBatch(request.context.selectedItems, hidden: false)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "已取消隐藏",
                failurePrefix: "取消隐藏未完全完成"
            )

        case .deletePermanently:
            let batch = try fileService.deleteBatch(request.context.selectedItems)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "已永久删除",
                failurePrefix: "删除未完全完成"
            )

        case .undoOperation:
            throw ActionRunnerError.unsupportedAction(action.kind)

        case .runCommand:
            // 命令需要实时输出，由主 App 进程负责执行，XPC 服务不再处理。
            throw ActionRunnerError.unsupportedAction(action.kind)

        case .airDrop:
            // AirDrop 分享面板需要前台 App 展示，由主 App 进程处理。
            throw ActionRunnerError.unsupportedAction(action.kind)
        }
    }

    private func directoryURL(from action: RightClickAction, bookmarkAccess: AuthorizedBookmarkAccess) throws -> URL {
        guard let directoryID = action.payload.directoryID else {
            throw ActionRunnerError.missingPayload("directoryID")
        }
        do {
            return try bookmarkAccess.url(for: directoryID)
        } catch BookmarkError.missingBookmark(_) {
            throw ActionRunnerError.directoryNotFound(directoryID)
        } catch {
            throw error
        }
    }

    private func fileTemplate(from action: RightClickAction, config: RightClickConfig) throws -> FileTemplate {
        guard let templateID = action.payload.templateID else {
            throw ActionRunnerError.missingPayload("templateID")
        }
        guard let template = config.fileTemplates.first(where: { $0.id == templateID }) else {
            throw ActionRunnerError.templateNotFound(templateID)
        }
        return template
    }

    private func developerEntrypoint(from action: RightClickAction, config: RightClickConfig) throws -> DeveloperEntrypoint {
        guard let entrypointID = action.payload.developerEntrypointID else {
            throw ActionRunnerError.missingPayload("developerEntrypointID")
        }
        guard let entrypoint = config.developerEntrypoints.first(where: { $0.id == entrypointID }) else {
            throw ActionRunnerError.developerEntrypointNotFound(entrypointID)
        }
        return entrypoint
    }

    private func developerTargetURL(for entrypoint: DeveloperEntrypoint, context: FinderContext) -> URL {
        switch entrypoint.targetMode {
        case .dynamic:
            switch context.invocation {
            case .selection, .toolbar:
                return context.selectedItems.first ?? context.targetDirectory
            case .container:
                return context.targetDirectory
            }
        case .currentDirectory:
            return context.targetDirectory
        case .selectedItem:
            return context.selectedItems.first ?? context.targetDirectory
        case .selectedItemDirectory:
            return context.selectedItems.first?.deletingLastPathComponent() ?? context.targetDirectory
        }
    }

    /// 选中单个文件夹时把粘贴目标直接定为该文件夹，否则回到当前目录。
    private func pasteDestination(for context: FinderContext) -> URL {
        guard context.invocation == .selection,
              context.selectedItems.count == 1,
              let item = context.selectedItems.first
        else {
            return context.targetDirectory
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return context.targetDirectory
        }

        return item
    }

    private func actionResult(
        requestID: UUID,
        batch: FileOperationBatchResult,
        successMessage: String,
        failurePrefix: String
    ) -> ActionResult {
        guard !batch.failures.isEmpty else {
            return ActionResult(
                requestID: requestID,
                status: .success,
                message: successMessage,
                affectedURLs: batch.completed.map(\.destinationURL)
            )
        }

        let details = batch.failures.map { failure in
            let message = FullDiskAccessAdvisor.userFacingMessage(for: failure.asNSError)
            return "\(failure.sourceURL.lastPathComponent)：\(message)"
        }.joined(separator: "；")
        let completedCount = batch.completed.count
        let pendingCount = batch.remainingSourceURLs.count
        let message = "\(failurePrefix)（已完成 \(completedCount) 项，待重试 \(pendingCount) 项）：\(details)"
        return ActionResult(
            requestID: requestID,
            status: batch.failures.allSatisfy(\.isCancellation) ? .cancelled : .failure,
            message: message,
            affectedURLs: batch.completed.map(\.destinationURL),
            remainingURLs: batch.remainingSourceURLs
        )
    }
}
