import AppKit
import Foundation

// MARK: - Models

struct FolderUsage: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let sizeBytes: Int64
}

struct LargeFileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let sizeBytes: Int64
    let modified: Date?
    var isSelected: Bool = false

    var path: String { url.path }
}

enum DiskScope: String, CaseIterable, Identifiable {
    case home
    case downloads
    case documents
    case desktop
    case movies
    case music
    case pictures
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Toàn bộ Home"
        case .downloads: return "Downloads"
        case .documents: return "Documents"
        case .desktop: return "Desktop"
        case .movies: return "Movies"
        case .music: return "Music"
        case .pictures: return "Pictures"
        case .library: return "~/Library"
        }
    }

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .home: return home
        case .downloads: return home.appendingPathComponent("Downloads")
        case .documents: return home.appendingPathComponent("Documents")
        case .desktop: return home.appendingPathComponent("Desktop")
        case .movies: return home.appendingPathComponent("Movies")
        case .music: return home.appendingPathComponent("Music")
        case .pictures: return home.appendingPathComponent("Pictures")
        case .library: return home.appendingPathComponent("Library")
        }
    }

    static func matching(_ url: URL) -> DiskScope? {
        allCases.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }
    }
}

struct DiskTrashResult {
    let movedCount: Int
    let freedBytes: Int64
    let errors: [String]
}

// MARK: - Analyzer

enum DiskAnalyzer {
    /// Dung lượng của từng thư mục con trực tiếp trong `root`.
    static func folderUsage(of root: URL) async -> [FolderUsage] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        let folders = entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }

        return await withTaskGroup(of: FolderUsage?.self) { group in
            for url in folders {
                group.addTask {
                    if Task.isCancelled { return nil }
                    let size = AppScanner.allocatedSize(of: url)
                    guard size > 0 else { return nil }
                    return FolderUsage(
                        id: url.standardizedFileURL.path,
                        url: url.standardizedFileURL,
                        name: url.lastPathComponent,
                        sizeBytes: size
                    )
                }
            }

            var result: [FolderUsage] = []
            for await item in group {
                if let item { result.append(item) }
            }
            return result.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    /// Các tệp đơn lẻ lớn hơn `minSize` trong `root`.
    static func largeFiles(in root: URL, minSize: Int64, limit: Int = 400) -> [LargeFileItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [LargeFileItem] = []

        for case let url as URL in enumerator {
            if Task.isCancelled { break }

            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .contentModificationDateKey
            ]), values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSize else { continue }

            files.append(
                LargeFileItem(
                    id: url.standardizedFileURL.path,
                    url: url.standardizedFileURL,
                    name: url.lastPathComponent,
                    sizeBytes: size,
                    modified: values.contentModificationDate,
                    isSelected: false
                )
            )

            if files.count > 5000 {
                files.sort { $0.sizeBytes > $1.sizeBytes }
                files = Array(files.prefix(limit * 2))
            }
        }

        return Array(files.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    // MARK: Removal

    static func isSafeToTrash(_ url: URL) -> Bool {
        let fm = FileManager.default
        let path = url.standardizedFileURL.path
        guard fm.fileExists(atPath: path) else { return false }

        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path != home, path.hasPrefix(home + "/") else { return false }
        guard !path.contains("/.Trash/") else { return false }
        guard !path.hasPrefix(home + "/Library/Keychains") else { return false }
        guard !path.hasPrefix(home + "/Library/Application Support/MobileSync") else { return false }
        guard path != Bundle.main.bundleURL.standardizedFileURL.path else { return false }

        // Không cho xoá chính các thư mục gốc của người dùng.
        let protectedFolders = [
            "Desktop", "Documents", "Downloads", "Library",
            "Pictures", "Movies", "Music", "Public", "Applications"
        ]
        if protectedFolders.contains(where: { path == home + "/" + $0 }) {
            return false
        }

        return true
    }

    static func moveToTrash(_ files: [LargeFileItem]) async -> DiskTrashResult {
        let fm = FileManager.default
        var movedCount = 0
        var freedBytes: Int64 = 0
        var errors: [String] = []

        for file in files {
            guard isSafeToTrash(file.url) else {
                errors.append("Bỏ qua vì lý do an toàn: \(file.name)")
                continue
            }
            do {
                try fm.trashItem(at: file.url, resultingItemURL: nil)
                movedCount += 1
                freedBytes += file.sizeBytes
            } catch {
                errors.append("\(file.name): \(error.localizedDescription)")
            }
        }

        return DiskTrashResult(movedCount: movedCount, freedBytes: freedBytes, errors: errors)
    }

    static func estimatedRootSize(_ folders: [FolderUsage]) -> Int64 {
        folders.reduce(0) { $0 + $1.sizeBytes }
    }
}
