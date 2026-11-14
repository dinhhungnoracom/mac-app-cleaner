import AppKit
import Foundation

struct TrashItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let sizeBytes: Int64
    let dateAddedToTrash: Date?
    let isDirectory: Bool
    var isSelected: Bool = false

    var path: String { url.path }
}

enum TrashService {
    static var trashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    static func scanTrash() async -> (items: [TrashItem], permissionDenied: Bool) {
        let fm = FileManager.default
        let root = trashURL.standardizedFileURL

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .addedToDirectoryDateKey,
                    .contentModificationDateKey,
                    .creationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
        } catch let err as NSError {
            let denied = (err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError)
                || (err.domain == NSPOSIXErrorDomain && (err.code == EPERM || err.code == EACCES))
            return ([], denied)
        }

        let items = await withTaskGroup(of: TrashItem.self, returning: [TrashItem].self) { group in
            for url in entries {
                group.addTask {
                    let values = try? url.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .addedToDirectoryDateKey,
                        .contentModificationDateKey,
                        .creationDateKey
                    ])
                    let isDir = values?.isDirectory ?? false
                    let date = values?.addedToDirectoryDate
                        ?? values?.contentModificationDate
                        ?? values?.creationDate
                    let size = FastDiskSize.allocatedSize(of: url)
                    return TrashItem(
                        id: url.standardizedFileURL.path,
                        name: url.lastPathComponent,
                        url: url.standardizedFileURL,
                        sizeBytes: size,
                        dateAddedToTrash: date,
                        isDirectory: isDir,
                        isSelected: false
                    )
                }
            }

            var collected: [TrashItem] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.sizeBytes > $1.sizeBytes }
        }

        return (items, false)
    }

    static func isSafeTrashChild(_ url: URL) -> Bool {
        let stdTrash = trashURL.standardizedFileURL.path
        let stdTarget = url.standardizedFileURL.path
        guard stdTarget != stdTrash else { return false }
        guard url.standardizedFileURL.deletingLastPathComponent().path == stdTrash else { return false }
        return FileManager.default.fileExists(atPath: stdTarget)
    }

    static func deleteItems(_ items: [TrashItem]) async -> (deletedCount: Int, freedBytes: Int64, errors: [String]) {
        let fm = FileManager.default
        var deletedCount = 0
        var freedBytes: Int64 = 0
        var errors: [String] = []

        for item in items {
            guard isSafeTrashChild(item.url) else {
                errors.append("Đường dẫn không hợp lệ: \(item.name)")
                continue
            }
            do {
                try fm.removeItem(at: item.url)
                deletedCount += 1
                freedBytes += item.sizeBytes
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return (deletedCount, freedBytes, errors)
    }

    static func emptyEntireTrash() async -> (ok: Bool, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]

        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            // Đọc hết pipe TRƯỚC khi waitUntilExit để tránh deadlock khi output > 64 KB.
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, nil)
            }
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, errText?.isEmpty == false ? errText : "Không thể dọn sạch Thùng rác.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func openTrashInFinder() {
        NSWorkspace.shared.open(trashURL)
    }
}
