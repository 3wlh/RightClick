# Directory Structure

RightClick is a small single Swift package. Keep ownership boundaries clear instead of creating nested feature directories prematurely.

## SwiftPM Targets

- `RightClickCore` is the shared library. Put Codable models, storage, menu projection, authorization, file operations, ActionRunner logic, XPC DTOs/adapters, and test doubles here.
- `RightClickAppPreview` is the menu-bar SwiftUI preview app and settings window. It may import AppKit/SwiftUI and `RightClickCore`, but it should not own Core persistence or file-operation rules.
- `RightClickFinderExtension` renders Finder menus and forwards actions to XPC. It may import AppKit/FinderSync and `RightClickCore`; it must not perform file mutations directly.
- `RightClickActionRunnerService` is the XPC process entry point. Keep it thin: construct runtime dependencies, export the XPC adapter, and run the listener.
- `RightClickCoreTests` contains XCTest coverage for Core behavior. New Core behavior should be testable without launching Finder or SwiftUI.

Reference files: `Package.swift`, `Sources/RightClickCore/ActionRunner.swift`, `Sources/RightClickFinderExtension/FinderSyncController.swift`, `Sources/RightClickActionRunnerService/main.swift`.

## File Ownership Rules

- Put shared contracts in `RightClickCore`, not in the app or extension. Examples: `RightClickAction`, `FinderContext`, `ActionRequest`, `ActionResult`, `MenuIconDescriptor`.
- Keep process-specific rendering at the process boundary. Core emits `MenuPresentation`; Finder extension turns it into `NSMenu`/`NSImage`.
- Keep runtime construction centralized in `RightClickRuntimeFactory` unless a target has a very small process-only setup, as in `RightClickActionRunnerService/main.swift`.
- Put test doubles next to Core when they are useful for many tests: `InMemoryOperationLog`, `InMemoryCutClipboardStore`, `RecordingURLOpener`, `StaticRightClickConfigProvider`.
- Keep shell packaging logic under `scripts/`; do not move preview-bundle assembly into Swift until the project has a real Xcode app target.

## Naming Conventions

- Models are nouns: `RightClickConfig`, `DirectoryBookmark`, `OperationRecord`.
- Services and stores end with their role: `FileOperationService`, `JSONLineOperationLog`, `FileBackedCutClipboardStore`.
- Protocols describe capability: `RightClickConfigProviding`, `BookmarkResolving`, `OperationLogging`, `URLOpening`.
- Error enums end in `Error` and conform to `LocalizedError` when they surface to users or logs.
- Default/generated config IDs are stable kebab-case strings, for example `template-md`, `developer-terminal`, `open-directory-code`.

## Adding New Files

Add a new file only when it gives a real ownership boundary. Good candidates are new Core services, new XPC contracts, or a focused SwiftUI settings screen/helper file under `RightClickAppPreview`. Avoid creating generic `Utils.swift`; prefer capability-specific names such as `BookmarkModels.swift` or `Authorization.swift`.

When a new action kind is added, expect changes in at least:

- `ActionModels.swift`
- `ActionRunner.swift`
- `MenuBuilder.swift`
- `RightClickAppPreview.swift` and the focused `Sources/RightClickAppPreview/*Views.swift` / `SettingsViewModel.swift` files
- `Tests/RightClickCoreTests/*`
