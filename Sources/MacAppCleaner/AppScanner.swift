import AppKit
import CoreServices
import Foundation

enum AppScanner {
    static let genericNames: Set<String> = [
        "app", "mail", "notes", "music", "photos", "home", "books", "news",
        "tips", "maps", "clock", "weather", "stocks", "files", "finder",
        "safari", "system", "preview", "calendar", "contacts", "reminders",
        "messages", "terminal", "console", "activity", "helper", "launcher"
    ]

    static var librarySubdirs: [(category: String, url: URL)] {
        let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let names = [
            "Application Support",
            "Caches",
            "Preferences",
            "Containers",
            "Group Containers",
            "Logs",
            "Saved Application State",
            "HTTPStorages",
            "WebKit",
            "LaunchAgents"
        ]
        return names.map { ($0, lib.appendingPathComponent($0)) }
    }

    static func getDiskStats() -> DiskStats? {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return nil
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let avail = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        guard total > 0 else { return nil }
        return DiskStats(totalBytes: total, availableBytes: avail)
    }

    static func scanApplications() async -> [InstalledApp] {
        let fm = FileManager.default
        let userAppsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            userAppsURL,
            URL(fileURLWithPath: "/System/Applications")
        ]

        var appURLs: [URL] = []
        for root in roots {
            collectAppBundles(in: root, maxDepth: 2, currentDepth: 0, results: &appURLs)
        }

        // Deduplicate by standardized path
        var seenPaths = Set<String>()
        let uniqueURLs = appURLs.filter { url in
            let std = url.standardizedFileURL.path
            return seenPaths.insert(std).inserted
        }

        let brewMap = loadBrewCaskTokens()
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )
        let runningBundleURLs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path }
        )

        return await withTaskGroup(of: InstalledApp?.self, returning: [InstalledApp].self) { group in
            for url in uniqueURLs {
                group.addTask {
                    inspectApp(
                        at: url,
                        userAppsPath: userAppsURL.standardizedFileURL.path,
                        brewMap: brewMap,
                        runningBundleIDs: runningBundleIDs,
                        runningBundleURLs: runningBundleURLs
                    )
                }
            }

            var results: [InstalledApp] = []
            for await item in group {
                if let item {
                    results.append(item)
                }
            }
            return results.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    private static func collectAppBundles(
        in directory: URL,
        maxDepth: Int,
        currentDepth: Int,
        results: inout [URL]
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            if entry.pathExtension.lowercased() == "app" {
                results.append(entry)
            } else if currentDepth < maxDepth - 1 {
                collectAppBundles(
                    in: entry,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1,
                    results: &results
                )
            }
        }
    }

    private static func inspectApp(
        at url: URL,
        userAppsPath: String,
        brewMap: [String: String],
        runningBundleIDs: Set<String>,
        runningBundleURLs: Set<String>
    ) -> InstalledApp? {
        let stdPath = url.standardizedFileURL.path
        let folderName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]

        let displayName = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleName = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [displayName, bundleName, folderName]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? folderName

        let bundleID = bundle?.bundleIdentifier ?? (info["CFBundleIdentifier"] as? String) ?? ""
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "—"

        let isSystem = stdPath.hasPrefix("/System/")
            || stdPath.hasPrefix("/Applications/Utilities")
            || stdPath == "/Applications/Safari.app"

        let isSelf = bundleID == "local.dinhdoong.MacAppCleaner"
            || stdPath == Bundle.main.bundleURL.standardizedFileURL.path
        let isProtected = isSystem || isSelf
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        let isAppStore = FileManager.default.fileExists(atPath: receiptURL.path)

        let brewToken = brewMap[normalize(folderName)] ?? brewMap[normalize(name)]

        let source: AppSource
        if isSystem {
            source = .system
        } else if isAppStore {
            source = .appStore
        } else if brewToken != nil {
            source = .homebrew
        } else {
            source = .direct
        }

        let locationLabel: String
        if stdPath.hasPrefix(userAppsPath) {
            locationLabel = "~/Applications"
        } else if stdPath.hasPrefix("/System/") {
            locationLabel = "/System/Applications"
        } else {
            locationLabel = "/Applications"
        }

        let arch = detectArchitecture(bundle: bundle)
        let sizeBytes = allocatedSize(of: url)
        let (lastUsedDate, dateAdded) = readSpotlightDates(for: url)

        let isRunning = (!bundleID.isEmpty && runningBundleIDs.contains(bundleID))
            || runningBundleURLs.contains(stdPath)

        return InstalledApp(
            id: stdPath,
            name: name,
            folderName: folderName,
            url: url.standardizedFileURL,
            locationLabel: locationLabel,
            bundleID: bundleID,
            version: version,
            sizeBytes: sizeBytes,
            lastUsedDate: lastUsedDate,
            dateAdded: dateAdded,
            source: source,
            brewToken: brewToken,
            arch: arch,
            isSystem: isSystem,
            isProtected: isProtected,
            isRunning: isRunning
        )
    }

    private static func detectArchitecture(bundle: Bundle?) -> CpuArch {
        guard let archs = bundle?.executableArchitectures?.map({ $0.intValue }), !archs.isEmpty else {
            return .unknown
        }
        let hasARM64 = archs.contains(NSBundleExecutableArchitectureARM64)
        let hasX86 = archs.contains(NSBundleExecutableArchitectureX86_64)
        if hasARM64 && hasX86 { return .universal }
        if hasARM64 { return .appleSilicon }
        if hasX86 { return .intel }
        return .unknown
    }

    private static func readSpotlightDates(for url: URL) -> (Date?, Date?) {
        var lastUsed: Date?
        var dateAdded: Date?

        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
            dateAdded = MDItemCopyAttribute(mdItem, kMDItemDateAdded) as? Date
        }

        if dateAdded == nil {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            dateAdded = values?.creationDate ?? values?.contentModificationDate
        }

        return (lastUsed, dateAdded)
    }

    private static func loadBrewCaskTokens() -> [String: String] {
        let roots = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom"
        ]
        var map: [String: String] = [:]
        let fm = FileManager.default
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for token in items where !token.hasPrefix(".") {
                map[normalize(token)] = token
            }
        }
        return map
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey
            ]), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func findLeftovers(for app: InstalledApp) async -> [LeftoverItem] {
        let fm = FileManager.default
        let bundleLower = app.bundleID.lowercased()
        let appNameLower = app.name.lowercased()
        let folderNameLower = app.folderName.lowercased()

        var matchNames = Set<String>()
        if appNameLower.count >= 4, !genericNames.contains(appNameLower) {
            matchNames.insert(appNameLower)
        }
        if folderNameLower.count >= 4, !genericNames.contains(folderNameLower) {
            matchNames.insert(folderNameLower)
        }

        var candidates: [(category: String, name: String, url: URL)] = []

        for sub in librarySubdirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: sub.url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for entry in entries {
                let entryName = entry.lastPathComponent
                let entryLower = entryName.lowercased()
                let stripped: String
                if entryLower.hasSuffix(".plist") {
                    stripped = String(entryLower.dropLast(6))
                } else if entryLower.hasSuffix(".savedstate") {
                    stripped = String(entryLower.dropLast(11))
                } else {
                    stripped = entryLower
                }

                var matched = false
                if bundleLower.count >= 5 {
                    if entryLower == bundleLower
                        || stripped == bundleLower
                        || entryLower.hasPrefix(bundleLower + ".")
                        || entryLower.hasPrefix(bundleLower + "-")
                        || (sub.category == "Group Containers" && entryLower.hasSuffix("." + bundleLower)) {
                        matched = true
                    }
                }

                if !matched, !matchNames.isEmpty {
                    if matchNames.contains(entryLower) || matchNames.contains(stripped) {
                        matched = true
                    }
                }

                if matched {
                    candidates.append((sub.category, entryName, entry))
                }
            }
        }

        return await withTaskGroup(of: LeftoverItem.self, returning: [LeftoverItem].self) { group in
            for c in candidates {
                group.addTask {
                    let size = allocatedSize(of: c.url)
                    return LeftoverItem(
                        id: c.url.path,
                        category: c.category,
                        name: c.name,
                        url: c.url,
                        sizeBytes: size,
                        isSelected: !app.isProtected
                    )
                }
            }

            var items: [LeftoverItem] = []
            for await item in group {
                items.append(item)
            }
            return items.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }
}
