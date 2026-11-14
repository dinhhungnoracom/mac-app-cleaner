import AppKit
import Foundation

// MARK: - Models

enum JunkCategory: String, CaseIterable, Identifiable {
    case caches
    case logs
    case xcode
    case deviceBackups
    case browserCaches
    case containerCaches
    case oldDownloads
    case orphaned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: return "Cache ứng dụng"
        case .logs: return "Logs & báo cáo lỗi"
        case .xcode: return "Xcode & Simulator"
        case .deviceBackups: return "Sao lưu iPhone / iPad"
        case .browserCaches: return "Cache trình duyệt"
        case .containerCaches: return "Cache trong Containers"
        case .oldDownloads: return "Tệp tải về cũ"
        case .orphaned: return "Rác mồ côi"
        }
    }

    var subtitle: String {
        switch self {
        case .caches: return "Dữ liệu tạm trong ~/Library/Caches, ứng dụng sẽ tự tạo lại khi cần."
        case .logs: return "Log và báo cáo sự cố trong ~/Library/Logs."
        case .xcode: return "DerivedData, DeviceSupport và cache Simulator của Xcode."
        case .deviceBackups: return "Bản sao lưu thiết bị iOS lưu trên máy — thường rất nặng."
        case .browserCaches: return "Cache của Safari, Chrome, Edge, Firefox, Brave, Arc..."
        case .containerCaches: return "Cache riêng của từng ứng dụng sandbox trong Containers."
        case .oldDownloads: return "Tệp trong ~/Downloads không đụng tới hơn 90 ngày (tự tắt mặc định)."
        case .orphaned: return "Thư mục còn sót lại của ứng dụng đã gỡ — nên kiểm tra kỹ trước khi xoá."
        }
    }

    var symbol: String {
        switch self {
        case .caches: return "shippingbox"
        case .logs: return "doc.text.magnifyingglass"
        case .xcode: return "hammer"
        case .deviceBackups: return "iphone.gen3"
        case .browserCaches: return "safari"
        case .containerCaches: return "square.stack.3d.up"
        case .oldDownloads: return "arrow.down.circle"
        case .orphaned: return "questionmark.folder"
        }
    }

    /// Nhóm chứa dữ liệu người dùng hoặc kết quả suy đoán: mặc định không chọn sẵn.
    var requiresReview: Bool {
        self == .oldDownloads || self == .orphaned
    }
}

struct JunkItem: Identifiable, Hashable {
    let id: String
    let category: JunkCategory
    let name: String
    let url: URL
    let sizeBytes: Int64
    let modified: Date?
    let detail: String
    var isSelected: Bool

    var path: String { url.path }
}

struct JunkGroup: Identifiable {
    let category: JunkCategory
    var items: [JunkItem]
    var isExpanded: Bool = false

    var id: String { category.id }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var selectedItems: [JunkItem] { items.filter(\.isSelected) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.isSelected) }
}

struct JunkRemovalResult {
    let removedPaths: Set<String>
    let freedBytes: Int64
    let errors: [String]

    var removedCount: Int { removedPaths.count }
}

// MARK: - Scanner

enum CleanupScanner {
    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    static let browserCacheRelativePaths: [(path: String, name: String)] = [
        ("Library/Caches/com.apple.Safari", "Safari"),
        ("Library/Caches/Google/Chrome", "Google Chrome"),
        ("Library/Caches/com.google.Chrome", "Google Chrome (cũ)"),
        ("Library/Caches/Microsoft Edge", "Microsoft Edge"),
        ("Library/Caches/Firefox", "Firefox"),
        ("Library/Caches/BraveSoftware", "Brave"),
        ("Library/Caches/com.operasoftware.Opera", "Opera"),
        ("Library/Caches/Arc", "Arc"),
        ("Library/Caches/com.microsoft.edgemac", "Microsoft Edge (cũ)")
    ]

    /// Các thư mục trong ~/Library có thể chứa tàn dư của ứng dụng đã gỡ.
    private static let orphanRootRelativePaths: [(path: String, label: String)] = [
        ("Library/Application Support", "Application Support"),
        ("Library/Preferences", "Preferences"),
        ("Library/Containers", "Containers"),
        ("Library/Group Containers", "Group Containers"),
        ("Library/Saved Application State", "Saved State"),
        ("Library/HTTPStorages", "HTTPStorages"),
        ("Library/WebKit", "WebKit"),
        ("Library/LaunchAgents", "LaunchAgents")
    ]

    static func scan(
        categories: Set<JunkCategory>,
        installedBundleIDs: Set<String>
    ) async -> [JunkGroup] {
        var groups: [JunkGroup] = []

        await withTaskGroup(of: JunkGroup?.self) { group in
            for category in JunkCategory.allCases where categories.contains(category) {
                group.addTask {
                    await scanCategory(category, installedBundleIDs: installedBundleIDs)
                }
            }

            for await result in group {
                if let result, !result.items.isEmpty {
                    groups.append(result)
                }
            }
        }

        let order = Dictionary(
            uniqueKeysWithValues: JunkCategory.allCases.enumerated().map { ($1, $0) }
        )
        return groups.sorted { (order[$0.category] ?? 0) < (order[$1.category] ?? 0) }
    }

    private static func scanCategory(
        _ category: JunkCategory,
        installedBundleIDs: Set<String>
    ) async -> JunkGroup? {
        switch category {
        case .caches:
            let root = home.appendingPathComponent("Library/Caches")
            let browserRoots = browserCacheRelativePaths.map {
                home.appendingPathComponent($0.path).standardizedFileURL.path
            }
            let urls = directChildren(of: root).filter { url in
                let path = url.standardizedFileURL.path
                guard !path.contains("MacAppCleaner") else { return false }
                // Không hiển thị trùng với nhóm "Cache trình duyệt".
                let overlapsBrowser = browserRoots.contains { browser in
                    browser == path || browser.hasPrefix(path + "/")
                }
                return !overlapsBrowser
            }
            return await makeGroup(category, from: urls.map { ($0, "Cache") })

        case .logs:
            let root = home.appendingPathComponent("Library/Logs")
            let urls = directChildren(of: root)
            return await makeGroup(category, from: urls.map { ($0, "Log") })

        case .xcode:
            let roots: [(String, String)] = [
                ("Library/Developer/Xcode/DerivedData", "DerivedData"),
                ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport"),
                ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS DeviceSupport"),
                ("Library/Developer/Xcode/tvOS DeviceSupport", "tvOS DeviceSupport"),
                ("Library/Developer/CoreSimulator/Caches", "Simulator Caches")
            ]
            var entries: [(URL, String)] = []
            for (relative, label) in roots {
                let dir = home.appendingPathComponent(relative)
                for url in directChildren(of: dir) {
                    entries.append((url, label))
                }
            }
            return await makeGroup(category, from: entries)

        case .deviceBackups:
            let root = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
            let urls = directChildren(of: root)
            return await makeGroup(category, from: urls.map { ($0, "iOS Backup") })

        case .browserCaches:
            var entries: [(URL, String)] = []
            for item in browserCacheRelativePaths {
                let dir = home.appendingPathComponent(item.path)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                entries.append((dir, item.name))
            }
            let names = Dictionary(uniqueKeysWithValues: entries.map {
                ($0.0.standardizedFileURL.path, $0.1)
            })
            return await makeGroup(category, from: entries, displayNames: names)

        case .containerCaches:
            let containers = home.appendingPathComponent("Library/Containers")
            var entries: [(URL, String)] = []
            for container in directChildren(of: containers) {
                let cache = container
                    .appendingPathComponent("Data/Library/Caches")
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: cache.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                entries.append((cache, container.lastPathComponent))
            }
            let names = Dictionary(uniqueKeysWithValues: entries.map {
                ($0.0.standardizedFileURL.path, $0.1)
            })
            return await makeGroup(
                category,
                from: entries.map { ($0.0, "Cache trong Container") },
                minimumSize: 5 * 1024 * 1024,
                displayNames: names
            )

        case .oldDownloads:
            let root = home.appendingPathComponent("Downloads")
            let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            let urls = directChildren(of: root).filter { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
                let date = values?.contentModificationDate ?? values?.addedToDirectoryDate
                guard let date else { return false }
                return date < cutoff
            }
            return await makeGroup(category, from: urls.map { ($0, "Downloads khác 90 ngày") })

        case .orphaned:
            return await scanOrphans(installedBundleIDs: installedBundleIDs)
        }
    }

    // MARK: Orphan detection

    private static func scanOrphans(installedBundleIDs: Set<String>) async -> JunkGroup? {
        var known = installedBundleIDs.filter { !$0.isEmpty }
        known.insert("local.dinhdoong.MacAppCleaner")

        // Mọi tiền tố của bundle id đang cài: "com.foo.bar.helper" => com, com.foo, com.foo.bar
        var knownPrefixes = Set<String>()
        var vendorPrefixes = Set<String>()
        for identifier in known {
            let parts = identifier.split(separator: ".")
            for index in 1...parts.count {
                knownPrefixes.insert(parts.prefix(index).joined(separator: "."))
            }
            if parts.count >= 2 {
                vendorPrefixes.insert(parts.prefix(2).joined(separator: "."))
            }
        }

        var found: [(URL, String)] = []

        for root in orphanRootRelativePaths {
            let dir = home.appendingPathComponent(root.path)
            for entry in directChildren(of: dir) {
                let name = entry.lastPathComponent
                guard name.count >= 6, !name.hasPrefix(".") else { continue }
                guard let candidate = bundleCandidate(from: name) else { continue }
                guard !isAppleIdentifier(candidate) else { continue }
                if hasOwner(candidate, known: known, prefixes: knownPrefixes, vendors: vendorPrefixes) {
                    continue
                }
                found.append((entry, root.label))
            }
        }

        guard !found.isEmpty else { return nil }

        var items: [JunkItem] = []
        await withTaskGroup(of: JunkItem?.self) { group in
            for (url, label) in found {
                group.addTask {
                    let size = AppScanner.allocatedSize(of: url)
                    guard size >= 1024 * 1024 else { return nil }
                    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return JunkItem(
                        id: url.standardizedFileURL.path,
                        category: .orphaned,
                        name: url.lastPathComponent,
                        url: url.standardizedFileURL,
                        sizeBytes: size,
                        modified: modified,
                        detail: label,
                        isSelected: false
                    )
                }
            }
            for await item in group {
                if let item { items.append(item) }
            }
        }

        guard !items.isEmpty else { return nil }
        return JunkGroup(
            category: .orphaned,
            items: items.sorted { $0.sizeBytes > $1.sizeBytes },
            isExpanded: false
        )
    }

    /// Rút bundle identifier từ tên thư mục / plist trong ~/Library.
    private static func bundleCandidate(from rawName: String) -> String? {
        var name = rawName
        if name.hasSuffix(".plist") { name = String(name.dropLast(6)) }
        if name.hasSuffix(".savedState") { name = String(name.dropLast(11)) }
        if name.hasSuffix(".binarycookies") { return nil }

        // Group Containers: "TEAMID1234.group.com.foo.bar" hoặc "TEAMID1234.com.foo.bar"
        if let range = name.range(of: "^[A-Z0-9]{8,10}\\.", options: .regularExpression) {
            name.removeSubrange(range)
        }
        // Một số app dùng tiền tố "group." cho Group Containers
        if name.hasPrefix("group.") { name = String(name.dropFirst(6)) }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard name.split(separator: ".").count >= 3 else { return nil }
        guard let first = name.first, first.isLetter else { return nil }
        return name
    }

    private static func isAppleIdentifier(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        return lowered.hasPrefix("com.apple.")
            || lowered.hasPrefix("apple.")
            || lowered.contains(".apple.")
            || lowered.hasPrefix("com.apple")
    }

    private static func hasOwner(
        _ candidate: String,
        known: Set<String>,
        prefixes: Set<String>,
        vendors: Set<String>
    ) -> Bool {
        if known.contains(candidate) { return true }
        // Ứng dụng còn cài có bundle id mở rộng từ candidate (helper, extension...)
        if prefixes.contains(candidate) { return true }

        let parts = candidate.split(separator: ".")
        // Candidate là helper/extension của một bundle id đang cài
        for index in 1..<parts.count {
            let prefix = parts.prefix(index).joined(separator: ".")
            if known.contains(prefix) { return true }
        }
        // Cùng nhà phát hành (com.docker.*, com.google.*) => coi như còn chủ
        if parts.count >= 3 {
            let vendor = parts.prefix(2).joined(separator: ".")
            if vendors.contains(vendor) { return true }
        }
        return false
    }

    // MARK: Helpers

    private static func directChildren(of directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return values?.isSymbolicLink != true
        }
    }

    private static func makeGroup(
        _ category: JunkCategory,
        from entries: [(URL, String)],
        minimumSize: Int64 = 0,
        displayNames: [String: String] = [:]
    ) async -> JunkGroup? {
        guard !entries.isEmpty else { return nil }

        var items: [JunkItem] = []
        await withTaskGroup(of: JunkItem?.self) { group in
            for (url, detail) in entries {
                group.addTask {
                    let size = AppScanner.allocatedSize(of: url)
                    guard size > 0, size >= minimumSize else { return nil }
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    let displayName = displayNames[url.standardizedFileURL.path] ?? url.lastPathComponent
                    return JunkItem(
                        id: url.standardizedFileURL.path,
                        category: category,
                        name: displayName,
                        url: url.standardizedFileURL,
                        sizeBytes: size,
                        modified: values?.contentModificationDate,
                        detail: detail,
                        isSelected: !category.requiresReview
                    )
                }
            }
            for await item in group {
                if let item { items.append(item) }
            }
        }

        guard !items.isEmpty else { return nil }
        return JunkGroup(
            category: category,
            items: items.sorted { $0.sizeBytes > $1.sizeBytes },
            isExpanded: false
        )
    }
}

// MARK: - Safety

enum CleanupSafety {
    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    private static var browserRoots: [String] {
        CleanupScanner.browserCacheRelativePaths.map { home + "/" + $0.path }
    }

    private static var xcodeRoots: [String] {
        [
            home + "/Library/Developer/Xcode/DerivedData",
            home + "/Library/Developer/Xcode/iOS DeviceSupport",
            home + "/Library/Developer/Xcode/watchOS DeviceSupport",
            home + "/Library/Developer/Xcode/tvOS DeviceSupport",
            home + "/Library/Developer/CoreSimulator/Caches"
        ]
    }

    private static var orphanRoots: [String] {
        [
            home + "/Library/Application Support",
            home + "/Library/Preferences",
            home + "/Library/Containers",
            home + "/Library/Group Containers",
            home + "/Library/Saved Application State",
            home + "/Library/HTTPStorages",
            home + "/Library/WebKit",
            home + "/Library/LaunchAgents"
        ]
    }

    static func isSafeToRemove(_ item: JunkItem) -> Bool {
        isSafeToRemove(item.url, category: item.category)
    }

    static func isSafeToRemove(_ url: URL, category: JunkCategory) -> Bool {
        let fm = FileManager.default
        let path = url.standardizedFileURL.path
        guard fm.fileExists(atPath: path) else { return false }

        let home = self.home
        guard path != home, path.hasPrefix(home + "/") else { return false }
        guard !path.hasPrefix(home + "/Library/Keychains") else { return false }
        guard !path.contains("/.Trash/") else { return false }

        switch category {
        case .caches:
            return isDirectChild(path, of: home + "/Library/Caches")

        case .logs:
            return isDirectChild(path, of: home + "/Library/Logs")

        case .xcode:
            return xcodeRoots.contains { isDirectChild(path, of: $0) }

        case .deviceBackups:
            return isDirectChild(path, of: home + "/Library/Application Support/MobileSync/Backup")

        case .browserCaches:
            return browserRoots.contains(path)

        case .containerCaches:
            guard path.hasPrefix(home + "/Library/Containers/") else { return false }
            return path.hasSuffix("/Data/Library/Caches")

        case .oldDownloads:
            return isDirectChild(path, of: home + "/Downloads")

        case .orphaned:
            return orphanRoots.contains { isDirectChild(path, of: $0) }
        }
    }

    private static func isDirectChild(_ path: String, of root: String) -> Bool {
        (path as NSString).deletingLastPathComponent == root
    }
}

// MARK: - Removal

enum CleanupService {
    static func remove(items: [JunkItem], permanently: Bool) async -> JunkRemovalResult {
        let fm = FileManager.default
        var removedPaths = Set<String>()
        var freedBytes: Int64 = 0
        var errors: [String] = []

        for item in items {
            guard CleanupSafety.isSafeToRemove(item) else {
                errors.append("Bỏ qua vì lý do an toàn: \(item.name)")
                continue
            }

            if item.category == .oldDownloads {
                let values = try? item.url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values?.contentModificationDate,
                   Date().timeIntervalSince(modified) < 90 * 24 * 60 * 60 {
                    errors.append("Tệp vừa được dùng, bỏ qua: \(item.name)")
                    continue
                }
            }

            do {
                if permanently {
                    try fm.removeItem(at: item.url)
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                removedPaths.insert(item.id)
                freedBytes += item.sizeBytes
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return JunkRemovalResult(
            removedPaths: removedPaths,
            freedBytes: freedBytes,
            errors: errors
        )
    }
}
