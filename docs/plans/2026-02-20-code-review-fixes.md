# Code Review Fixes — 2026-02-20

## Scope
Fix all Critical and Important issues found in code review, plus minor cleanup.

---

## Batch 1 — Critical Fixes

### Task 1.1 — Fix bundle ID + pasteboard name in FinderSync.swift
- File: `MacApp/FinderExtension/FinderSync.swift:277,281`
- Change `"com.7zip.SevenZipMac"` → `"com.septazip.SeptaZip"`
- Change `NSPasteboard.Name("com.7zip.action")` → `NSPasteboard.Name("com.septazip.action")`

### Task 1.2 — Replace NSUserNotification with UNUserNotificationCenter
- File: `MacApp/FinderExtension/FinderSync.swift`
- Add `import UserNotifications`
- Request authorization in `init()`
- Replace `showNotification` to use `UNMutableNotificationContent`

### Task 1.3 — Fix waitUntilExit() blocking main thread in ArchiveManager.swift
- File: `MacApp/SevenZipMac/Models/ArchiveManager.swift:232`
- Replace `process.waitUntilExit()` with `process.terminationHandler`
- Move output reading + continuation.resume into the handler

---

## Batch 2 — Important Fixes

### Task 2.1 — Fix 1...0 crash in AppDelegate.swift
- File: `MacApp/SevenZipMac/App/AppDelegate.swift:33`
- Add `guard listDesc.numberOfItems > 0 else { return }` before the for loop

### Task 2.2 — Fix ArchiveManager instantiated in SettingsView body
- File: `MacApp/SevenZipMac/Views/SettingsView.swift:42-43`
- Add `@StateObject private var archiveManager = ArchiveManager()` property
- Replace inline `let manager = ArchiveManager()` with `archiveManager`

### Task 2.3 — Fix exit code check in compress-with-7zip.sh
- File: `MacApp/QuickActions/compress-with-7zip.sh:104`
- Change `[ $? -eq 0 ]` → `[ $? -le 1 ]` (treat 7-Zip exit code 1 as success)

---

## Batch 3 — Minor Cleanup

### Task 3.1 — Remove dead if/else in MainWindow.swift double-click handler
- File: `MacApp/SevenZipMac/Views/MainWindow.swift:337-341`
- Collapse redundant if/else into single assignment `currentPath = item.path`

### Task 3.2 — Remove redundant Window("Compress") scene from SevenZipApp.swift
- File: `MacApp/SevenZipMac/App/SevenZipApp.swift:44-49`
- Remove the `Window("Compress", id: "compress") { ... }` scene block

### Task 3.3 — Fix wrong project name in setup.sh
- File: `MacApp/Scripts/setup.sh:72-73`
- Change `SevenZipMac.xcodeproj` → `SeptaZip.xcodeproj`
- Change `SevenZipMac` scheme → `SeptaZip`
