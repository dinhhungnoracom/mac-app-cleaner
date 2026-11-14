import Foundation

/// Cache dung lượng thư mục để lần mở tab Ổ đĩa sau đó hiện ngay,
/// không phải quét lại từ đầu.
enum FolderSizeCache {
    struct Snapshot {
        let folders: [FolderUsage]
        let savedAt: Date

        var isFresh: Bool {
            Date().timeIntervalSince(savedAt) < 600
        }
    }

    private struct Entry: Codable {
        var savedAt: Date
        var sizes: [String: Int64]
    }

    private static let ttl: TimeInterval = 600

    private static var cacheFileURL: URL {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacAppCleaner", isDirectory: true)
        return base.appendingPathComponent("folder-size-cache.json")
    }

    static func load(root: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let all = try? JSONDecoder().decode([String: Entry].self, from: data),
              let entry = all[root.standardizedFileURL.path] else {
            return nil
        }

        let fm = FileManager.default
        let folders: [FolderUsage] = entry.sizes.compactMap { path, size in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let url = URL(fileURLWithPath: path)
            return FolderUsage(
                id: path,
                url: url,
                name: url.lastPathComponent,
                sizeBytes: size
            )
        }

        guard folders.count >= 2 else { return nil }
        return Snapshot(
            folders: folders.sorted { $0.sizeBytes > $1.sizeBytes },
            savedAt: entry.savedAt
        )
    }

    static func save(root: URL, folders: [FolderUsage]) {
        guard !folders.isEmpty else { return }

        var all: [String: Entry] = [:]
        if let data = try? Data(contentsOf: cacheFileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            all = decoded
        }

        let key = root.standardizedFileURL.path
        all[key] = Entry(
            savedAt: Date(),
            sizes: Dictionary(uniqueKeysWithValues: folders.map { ($0.url.standardizedFileURL.path, $0.sizeBytes) })
        )

        // Giữ tối đa 12 thư mục gần nhất để file cache không phình to.
        if all.count > 12 {
            let keep = all.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(12)
            all = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }

        let fm = FileManager.default
        let dir = cacheFileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    static func invalidate(root: URL) {
        guard let data = try? Data(contentsOf: cacheFileURL),
              var all = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return
        }
        all.removeValue(forKey: root.standardizedFileURL.path)
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }
}
