# File-Backed Storage Guidelines

RightClick has no database layer. Durable state is file-backed JSON/JSONL under `~/Library/Application Support/com.local.rightclick` by default so first launch does not touch `~/Library/Group Containers` and trigger macOS "access data from other apps" prompts.

## Storage Layout

`RightClickStoragePaths` defines the complete storage contract:

```text
baseURL/
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
└── command-runs/
```

Reference files: `Sources/RightClickCore/Storage.swift`, `OperationLogStore.swift`, `CutClipboardStore.swift`.

## JSON Stores

- Use `JSONFileStore<Value: Codable>` for structured JSON files.
- Writes must be atomic via `Data.write(..., .atomic)`.
- Use `load(default:)` for optional/defaulted state and `loadRequired()` only when absence is a hard failure.
- Keep JSON output pretty-printed and sorted through the existing `JSONFileStore` encoder.
- Do not hand-roll ad hoc JSON parsing or string replacement for `config.json` or `bookmarks.json`.

## Operation Log

- Use `JSONLineOperationLog` for `operation-log.jsonl`.
- Append by loading existing records, adding the new record, capping to `maxRecords`, and atomically rewriting the file.
- The default cap is 500 records. Settings UI currently displays the latest 80 in reverse chronological order.
- Invalid JSONL lines are ignored by `loadRecent()` through `try?`; do not make the UI fail just because one historical line is corrupt.

Reference tests: `Tests/RightClickCoreTests/StorageTests.swift`.

## Finder Icon Cache

Menu icons use an in-memory-only cache (`FinderSyncController.iconCache`).

- On startup and after every configuration change, the extension resolves
  real app/file icons for all enabled actions concurrently on the low-priority
  icon queue and stores rasterized menu-ready images in memory only.
- There is no persisted icon cache; do not reintroduce disk-backed icon
  caching without an invalidation story (stale icons outlive app updates).
- Menu callbacks must never resolve icons synchronously; if a key is not
  cached yet, render the placeholder and schedule async resolution.

## App Group and Fallback Rules

- Prefer `RightClickStoragePaths.defaultForCurrentProcess()` for production paths; it must resolve to the real-user Application Support directory, not the sandbox container home and not the App Group container.
- Use `RightClickStoragePaths.appGroup(identifier:)` only for explicit compatibility or diagnostics where absence should be reported as `StorageError.appGroupContainerUnavailable`.
- Use `RIGHTCLICKPRO_STORAGE_PATH` only for the ActionRunner process/testing override in `Sources/RightClickActionRunnerService/main.swift`.
- Default preview configuration may be created by either the app or Finder extension; both must use the same storage path resolution.
- Sandboxed App/Finder extension builds need a home-relative read-write entitlement only for `/Library/Application Support/com.local.rightclick/`.

## Config Repair Rules

`ConfigurationBootstrapper` is the only place that creates or repairs default config/bookmark state.

- Bootstrap must preserve unrelated user configuration.
- Missing available default bookmarks may be appended only on first creation or the one-time `.default-directory-bootstrap-v1` migration. Write the marker after bookmarks/config save successfully; subsequent bootstrap runs preserve user-deleted defaults.
- Missing monitored/common IDs for available defaults may be appended.
- Missing generated directory actions may be appended.
- Existing sandbox-container bookmark paths must be remapped to the real user home.
- Bookmark IDs, display names, bookmark data, and timestamps must be preserved during path sanitization.

Reference tests: `Tests/RightClickCoreTests/ConfigurationBootstrapperTests.swift`.

## Anti-Patterns

- Do not use `FileManager.homeDirectoryForCurrentUser` as the source of default monitored directories from sandboxed processes; use the bootstrapper's real-home resolution.
- Do not write storage files directly from child SwiftUI views.
- Do not remove or reorder unrelated user actions while repairing defaults.
- Do not introduce a database or migration framework until the JSON contract is proven insufficient.
