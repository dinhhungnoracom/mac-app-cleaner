import AppKit
import Foundation

struct RemovalResult {
    let movedCount: Int
    let freedBytes: Int64
    let errors: [String]
}

enum AppRemover {
    static func isSafeRemovableURL(_ url: URL) -> Bool {
        let resolved = url.standardizedFileURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: resolved) else { return false }

        if resolved.hasPrefix("/System") { return false }
        if resolved.hasPrefix("/Applications/Utilities") { return false }
        if resolved == "/Applications/Safari.app" { return false }
        if resolved == "/Applications/MacAppCleaner.app" { return false }
        if resolved == Bundle.main.bundleURL.standardizedFileURL.path { return false }

        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").standardizedFileURL.path
        if resolved.hasSuffix(".app") {
            if resolved.hasPrefix("/Applications/") || resolved.hasPrefix(userApps + "/") {
                return true
            }
        }

        for sub in AppScanner.librarySubdirs {
            let parent = sub.url.standardizedFileURL.path
            if resolved.hasPrefix(parent + "/") {
                return true
            }
        }

        return false
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    static func quitApp(_ app: InstalledApp) -> Bool {
        var terminated = false
        if !app.bundleID.isEmpty {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            for proc in running {
                if proc.terminate() {
                    terminated = true
                }
            }
        }
        if !terminated {
            let stdPath = app.url.standardizedFileURL.path
            for proc in NSWorkspace.shared.runningApplications {
                if proc.bundleURL?.standardizedFileURL.path == stdPath {
                    if proc.terminate() {
                        terminated = true
                    }
                }
            }
        }
        return terminated
    }

    static func moveToTrash(app: InstalledApp, leftovers: [LeftoverItem]) async -> RemovalResult {
        guard isSafeRemovableURL(app.url) else {
            return RemovalResult(
                movedCount: 0,
                freedBytes: 0,
                errors: ["Ứng dụng này được hệ thống bảo vệ, không thể gỡ bỏ."]
            )
        }

        if app.isRunning {
            _ = quitApp(app)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        var targets: [(url: URL, size: Int64)] = [(app.url, app.sizeBytes)]
        for item in leftovers where item.isSelected {
            targets.append((item.url, item.sizeBytes))
        }

        var movedCount = 0
        var freedBytes: Int64 = 0
        var errors: [String] = []

        for target in targets {
            guard isSafeRemovableURL(target.url) else {
                errors.append("Bỏ qua đường dẫn được bảo vệ: \(target.url.path)")
                continue
            }

            do {
                try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
                movedCount += 1
                freedBytes += target.size
            } catch {
                // Fallback to Finder AppleScript (handles root-owned /Applications bundles with native macOS auth prompt)
                if moveToTrashViaFinder(target.url) {
                    movedCount += 1
                    freedBytes += target.size
                } else {
                    errors.append("\(target.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return RemovalResult(movedCount: movedCount, freedBytes: freedBytes, errors: errors)
    }

    private static func moveToTrashViaFinder(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "on run argv\n  set targetItem to POSIX file (item 1 of argv)\n  tell application \"Finder\" to delete targetItem\nend run",
            url.standardizedFileURL.path
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
