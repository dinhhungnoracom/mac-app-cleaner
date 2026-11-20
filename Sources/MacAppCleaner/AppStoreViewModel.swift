import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppStoreViewModel: ObservableObject {
    @Published var activeTab: MainTab = .apps

    @Published var apps: [InstalledApp] = []
    @Published var diskStats: DiskStats?
    @Published var isScanning: Bool = false

    @Published var searchText: String = ""
    @Published var filter: AppFilter = .thirdParty
    @Published var sort: AppSort = .sizeDesc

    @Published var selectedAppID: String?
    @Published var leftovers: [LeftoverItem] = []
    @Published var isLoadingLeftovers: Bool = false

    @Published var isBulkMode: Bool = false
    @Published var bulkSelectedIDs: Set<String> = []

    @Published var trashItems: [TrashItem] = []
    @Published var isScanningTrash: Bool = false
    @Published var trashPermissionDenied: Bool = false
    @Published var trashSearchText: String = ""
    @Published var trashSort: TrashSort = .sizeDesc

    @Published var cpuMetrics: SystemCPUMetrics?
    @Published var memoryMetrics: SystemMemoryMetrics?
    @Published var processes: [ProcessItem] = []
    @Published var processFilter: ProcessFilter = .appsOnly
    @Published var processSort: ProcessSort = .cpuDesc
    @Published var processSearchText: String = ""
    @Published var isRefreshingMonitor: Bool = false

    // MARK: Cleanup tab
    @Published var cleanupGroups: [JunkGroup] = []
    @Published var isCleanupScanning: Bool = false
    @Published var cleanupLastScan: Date?
    @Published var cleanupHasScanned: Bool = false

    // MARK: Disk tab
    @Published var diskRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var diskMinSize: Int64 = 100 * 1024 * 1024
    @Published var diskFolders: [FolderUsage] = []
    @Published var diskLargeFiles: [LargeFileItem] = []
    @Published var diskSearchText: String = ""
    @Published var diskShowHiddenFolders: Bool = true
    @Published var isDiskScanning: Bool = false
    @Published var isDiskFolderScanning: Bool = false
    @Published var diskHasScanned: Bool = false
    private var diskScanGeneration = 0
    private var diskFolderTask: Task<Void, Never>?

    @Published var isRemoving: Bool = false
    @Published var statusBanner: (message: String, isError: Bool)?

    private var iconCache: [String: NSImage] = [:]
    private var monitorTimer: Timer?

    var selectedApp: InstalledApp? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID }
    }

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = apps.filter { app in
            switch filter {
            case .thirdParty:
                if app.isSystem { return false }
            case .large:
                if app.isSystem || app.sizeBytes < 500 * 1024 * 1024 { return false }
            case .unused:
                if !app.isUnused90Days { return false }
            case .homebrew:
                if app.source != .homebrew { return false }
            case .appStore:
                if app.source != .appStore { return false }
            case .all:
                break
            }

            if !query.isEmpty {
                let hay = "\(app.name) \(app.folderName) \(app.bundleID) \(app.path)".lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }

        switch sort {
        case .sizeDesc:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .unusedDesc:
            return filtered.sorted {
                ($0.lastUsedDate ?? .distantPast) < ($1.lastUsedDate ?? .distantPast)
            }
        case .nameAsc:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .addedDesc:
            return filtered.sorted {
                ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
            }
        }
    }

    var thirdPartyApps: [InstalledApp] {
        apps.filter { !$0.isSystem }
    }

    var thirdPartyTotalBytes: Int64 {
        thirdPartyApps.reduce(0) { $0 + $1.sizeBytes }
    }

    var unused90Count: Int {
        thirdPartyApps.filter { $0.isUnused90Days }.count
    }

    var selectedReclaimBytes: Int64 {
        guard let app = selectedApp else { return 0 }
        let leftoverBytes = leftovers.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
        return app.sizeBytes + leftoverBytes
    }

    var bulkSelectedApps: [InstalledApp] {
        apps.filter { bulkSelectedIDs.contains($0.id) && !$0.isProtected }
    }

    var bulkTotalBytes: Int64 {
        bulkSelectedApps.reduce(0) { $0 + $1.sizeBytes }
    }

    func icon(for app: InstalledApp) -> NSImage {
        icon(forPath: app.path)
    }

    func icon(forPath path: String) -> NSImage {
        if let cached = iconCache[path] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = img
        return img
    }

    var filteredTrashItems: [TrashItem] {
        let q = trashSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty
            ? trashItems
            : trashItems.filter { $0.name.lowercased().contains(q) }

        switch trashSort {
        case .sizeDesc:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .newestDesc:
            return filtered.sorted {
                ($0.dateAddedToTrash ?? .distantPast) > ($1.dateAddedToTrash ?? .distantPast)
            }
        case .nameAsc:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    var trashTotalBytes: Int64 {
        trashItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedTrashItems: [TrashItem] {
        trashItems.filter(\.isSelected)
    }

    var selectedTrashBytes: Int64 {
        selectedTrashItems.reduce(0) { $0 + $1.sizeBytes }
    }

    func refresh() async {
        isScanning = true
        defer { isScanning = false }

        async let scannedApps = Task.detached(priority: .userInitiated) {
            await AppScanner.scanApplications()
        }.value
        async let scannedTrash = Task.detached(priority: .userInitiated) {
            await TrashService.scanTrash()
        }.value

        let (appsResult, trashResult) = await (scannedApps, scannedTrash)
        apps = appsResult
        trashItems = trashResult.items
        trashPermissionDenied = trashResult.permissionDenied
        diskStats = AppScanner.getDiskStats()

        if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
            self.leftovers = []
        } else if let current = selectedApp {
            await loadLeftovers(for: current)
        }
    }

    func refreshTrash() async {
        isScanningTrash = true
        defer { isScanningTrash = false }

        let result = await Task.detached(priority: .userInitiated) {
            await TrashService.scanTrash()
        }.value

        trashItems = result.items
        trashPermissionDenied = result.permissionDenied
        diskStats = AppScanner.getDiskStats()
    }

    func toggleTrashSelection(_ item: TrashItem) {
        guard let idx = trashItems.firstIndex(where: { $0.id == item.id }) else { return }
        trashItems[idx].isSelected.toggle()
    }

    func selectAllFilteredTrash() {
        let visibleIDs = Set(filteredTrashItems.map(\.id))
        for idx in trashItems.indices where visibleIDs.contains(trashItems[idx].id) {
            trashItems[idx].isSelected = true
        }
    }

    func clearTrashSelection() {
        for idx in trashItems.indices {
            trashItems[idx].isSelected = false
        }
    }

    func deleteSelectedTrashItems() async {
        let targets = selectedTrashItems
        guard !targets.isEmpty else { return }

        isRemoving = true
        defer { isRemoving = false }

        let res = await Task.detached(priority: .userInitiated) {
            await TrashService.deleteItems(targets)
        }.value

        if res.deletedCount > 0 {
            showBanner(
                "Đã xoá vĩnh viễn \(res.deletedCount) mục (\(ByteFormat.string(from: res.freedBytes))) khỏi Thùng rác.",
                isError: !res.errors.isEmpty
            )
        } else {
            showBanner(res.errors.first ?? "Không thể xoá các mục đã chọn.", isError: true)
        }

        await refreshTrash()
    }

    func emptyEntireTrash() async {
        isRemoving = true
        defer { isRemoving = false }

        let prevBytes = trashTotalBytes
        let res = await Task.detached(priority: .userInitiated) {
            await TrashService.emptyEntireTrash()
        }.value

        if res.ok {
            let msg = prevBytes > 0
                ? "Đã dọn sạch toàn bộ Thùng rác (giải phóng \(ByteFormat.string(from: prevBytes)))!"
                : "Đã dọn sạch toàn bộ Thùng rác!"
            showBanner(msg, isError: false)
        } else {
            showBanner(res.error ?? "Không thể dọn sạch Thùng rác.", isError: true)
        }

        await refreshTrash()
    }

    func selectApp(_ app: InstalledApp) async {
        selectedAppID = app.id
        await loadLeftovers(for: app)
    }

    func loadLeftovers(for app: InstalledApp) async {
        isLoadingLeftovers = true
        leftovers = []

        let currentID = app.id
        let found = await Task.detached(priority: .userInitiated) {
            await AppScanner.findLeftovers(for: app)
        }.value

        guard selectedAppID == currentID else { return }
        leftovers = found
        isLoadingLeftovers = false
    }

    func toggleAllLeftovers() {
        let allSelected = leftovers.allSatisfy(\.isSelected)
        for idx in leftovers.indices {
            leftovers[idx].isSelected = !allSelected
        }
    }

    func toggleBulkSelection(for app: InstalledApp) {
        guard !app.isProtected else { return }
        if bulkSelectedIDs.contains(app.id) {
            bulkSelectedIDs.remove(app.id)
        } else {
            bulkSelectedIDs.insert(app.id)
        }
    }

    func selectAllFilteredForBulk() {
        for app in filteredApps where !app.isProtected {
            bulkSelectedIDs.insert(app.id)
        }
    }

    func clearBulkSelection() {
        bulkSelectedIDs.removeAll()
    }

    func quitSelectedApp() {
        guard let app = selectedApp else { return }
        if AppRemover.quitApp(app) {
            showBanner("Đã gửi lệnh thoát \(app.name)", isError: false)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                await refresh()
            }
        } else {
            showBanner("Không thể thoát \(app.name)", isError: true)
        }
    }

    func removeSelectedApp() async {
        guard let app = selectedApp, !app.isProtected else { return }
        isRemoving = true
        defer { isRemoving = false }

        let chosenLeftovers = leftovers
        let result = await Task.detached(priority: .userInitiated) {
            await AppRemover.moveToTrash(app: app, leftovers: chosenLeftovers)
        }.value

        if result.movedCount > 0 {
            showBanner(
                "Đã chuyển \(app.name) (\(result.movedCount) mục, \(ByteFormat.string(from: result.freedBytes))) vào Thùng rác.",
                isError: !result.errors.isEmpty
            )
        } else {
            showBanner(result.errors.first ?? "Không thể xoá ứng dụng.", isError: true)
        }

        await refresh()
    }

    func removeBulkSelectedApps() async {
        let targets = bulkSelectedApps
        guard !targets.isEmpty else { return }

        isRemoving = true
        defer { isRemoving = false }

        var totalMoved = 0
        var totalFreed: Int64 = 0
        var allErrors: [String] = []

        for app in targets {
            let foundLeftovers = await Task.detached(priority: .userInitiated) {
                await AppScanner.findLeftovers(for: app)
            }.value
            let result = await Task.detached(priority: .userInitiated) {
                await AppRemover.moveToTrash(app: app, leftovers: foundLeftovers)
            }.value
            totalMoved += result.movedCount
            totalFreed += result.freedBytes
            allErrors.append(contentsOf: result.errors)
        }

        bulkSelectedIDs.removeAll()
        if totalMoved > 0 {
            showBanner(
                "Đã chuyển \(targets.count) ứng dụng (\(ByteFormat.string(from: totalFreed))) vào Thùng rác.",
                isError: !allErrors.isEmpty
            )
        } else {
            showBanner(allErrors.first ?? "Không thể gỡ các ứng dụng đã chọn.", isError: true)
        }

        await refresh()
    }

    func showBanner(_ message: String, isError: Bool) {
        statusBanner = (message, isError)
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if statusBanner?.message == message {
                statusBanner = nil
            }
        }
    }

    // MARK: - Activity Monitor

    var filteredProcesses: [ProcessItem] {
        let q = processSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = processes.filter { item in
            if processFilter == .appsOnly {
                if !item.isGUIApp && item.appURL == nil { return false }
            }
            if !q.isEmpty {
                let pidStr = String(item.pid)
                let hay = "\(item.name) \(item.executablePath) \(pidStr)".lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }

        switch processSort {
        case .cpuDesc:
            return filtered.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memoryDesc:
            return filtered.sorted { $0.memoryBytes > $1.memoryBytes }
        case .nameAsc:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    func iconForProcess(_ item: ProcessItem) -> NSImage {
        if let url = item.appURL {
            return icon(forPath: url.path)
        }
        return icon(forPath: item.executablePath)
    }

    func refreshMonitor() async {
        guard !isRefreshingMonitor else { return }
        isRefreshingMonitor = true
        defer { isRefreshingMonitor = false }

        let cpu = await Task.detached(priority: .userInitiated) {
            SystemMonitorService.shared.getCPUMetrics()
        }.value

        let mem = await Task.detached(priority: .userInitiated) {
            SystemMonitorService.shared.getMemoryMetrics()
        }.value

        let procs = await Task.detached(priority: .userInitiated) {
            SystemMonitorService.shared.getProcesses()
        }.value

        self.cpuMetrics = cpu
        self.memoryMetrics = mem
        self.processes = procs
        self.diskStats = AppScanner.getDiskStats()
    }

    func startMonitorTimer() {
        stopMonitorTimer()
        Task { await refreshMonitor() }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeTab == .monitor else { return }
                await self.refreshMonitor()
            }
        }
        if let timer = monitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitorTimer() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func terminateProcess(_ item: ProcessItem, force: Bool) async {
        let success = await Task.detached(priority: .userInitiated) {
            SystemMonitorService.shared.terminateProcess(pid: item.pid, force: force)
        }.value

        if success {
            showBanner(
                force ? "Đã buộc dừng tiến trình \(item.name) (PID \(item.pid))" : "Đã gửi lệnh thoát \(item.name)",
                isError: false
            )
        } else {
            showBanner("Không thể thoát tiến trình \(item.name) (cần quyền root hoặc đã tắt)", isError: true)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        await refreshMonitor()
    }

    // MARK: - Cleanup

    var cleanupSelectedItems: [JunkItem] {
        cleanupGroups.flatMap(\.selectedItems)
    }

    var cleanupSelectedBytes: Int64 {
        cleanupGroups.reduce(0) { $0 + $1.selectedBytes }
    }

    var cleanupSelectedCount: Int {
        cleanupGroups.reduce(0) { $0 + $1.selectedItems.count }
    }

    var cleanupTotalBytes: Int64 {
        cleanupGroups.reduce(0) { $0 + $1.totalBytes }
    }

    var cleanupItemCount: Int {
        cleanupGroups.reduce(0) { $0 + $1.items.count }
    }

    func scanJunk() async {
        guard !isCleanupScanning else { return }
        isCleanupScanning = true
        defer { isCleanupScanning = false }

        var identifiers = Set(apps.map { $0.bundleID }.filter { !$0.isEmpty })
        identifiers.insert("local.dinhdoong.MacAppCleaner")

        let groups = await Task.detached(priority: .userInitiated) {
            await CleanupScanner.scan(
                categories: Set(JunkCategory.allCases),
                installedBundleIDs: identifiers
            )
        }.value

        cleanupGroups = groups
        cleanupLastScan = Date()
        cleanupHasScanned = true

        if groups.isEmpty {
            showBanner("Không tìm thấy dữ liệu rác đáng kể nào.", isError: false)
        } else {
            showBanner(
                "Đã quét \(groups.count) nhóm — tìm thấy \(ByteFormat.string(from: cleanupTotalBytes)) có thể dọn.",
                isError: false
            )
        }
    }

    func selectSafeJunk() {
        for groupIndex in cleanupGroups.indices {
            let safe = !cleanupGroups[groupIndex].category.requiresReview
            for itemIndex in cleanupGroups[groupIndex].items.indices {
                cleanupGroups[groupIndex].items[itemIndex].isSelected = safe
            }
        }
    }

    func clearJunkSelection() {
        for groupIndex in cleanupGroups.indices {
            for itemIndex in cleanupGroups[groupIndex].items.indices {
                cleanupGroups[groupIndex].items[itemIndex].isSelected = false
            }
        }
    }

    func toggleJunkGroup(_ groupID: String) {
        guard let index = cleanupGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let shouldSelect = !cleanupGroups[index].allSelected
        for itemIndex in cleanupGroups[index].items.indices {
            cleanupGroups[index].items[itemIndex].isSelected = shouldSelect
        }
    }

    func toggleJunkItem(_ item: JunkItem) {
        for groupIndex in cleanupGroups.indices {
            if let itemIndex = cleanupGroups[groupIndex].items.firstIndex(where: { $0.id == item.id }) {
                cleanupGroups[groupIndex].items[itemIndex].isSelected.toggle()
                return
            }
        }
    }

    func setAllJunkExpanded(_ expanded: Bool) {
        for index in cleanupGroups.indices {
            cleanupGroups[index].isExpanded = expanded
        }
    }

    func cleanSelectedJunk(permanently: Bool) async {
        let targets = cleanupSelectedItems
        guard !targets.isEmpty else { return }

        isRemoving = true
        defer { isRemoving = false }

        let result = await Task.detached(priority: .userInitiated) {
            await CleanupService.remove(items: targets, permanently: permanently)
        }.value

        for index in cleanupGroups.indices {
            cleanupGroups[index].items.removeAll { result.removedPaths.contains($0.id) }
        }
        cleanupGroups.removeAll { $0.items.isEmpty }

        if result.removedCount > 0 {
            let verb = permanently ? "Đã xoá vĩnh viễn" : "Đã chuyển vào Thùng rác"
            showBanner(
                "\(verb) \(result.removedCount) mục (\(ByteFormat.string(from: result.freedBytes))).",
                isError: !result.errors.isEmpty
            )
        } else {
            showBanner(result.errors.first ?? "Không thể dọn các mục đã chọn.", isError: true)
        }

        diskStats = AppScanner.getDiskStats()
    }

    // MARK: - Disk analyzer

    var diskRootLabel: String {
        if let scope = DiskScope.matching(diskRootURL) {
            return scope.title
        }
        return diskRootURL.lastPathComponent
    }

    var diskCanGoUp: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return diskRootURL.standardizedFileURL.path != home
    }

    var visibleDiskFolders: [FolderUsage] {
        guard !diskShowHiddenFolders else { return diskFolders }
        return diskFolders.filter { !$0.name.hasPrefix(".") }
    }

    var diskFoldersTotalBytes: Int64 {
        DiskAnalyzer.estimatedRootSize(visibleDiskFolders)
    }

    var filteredLargeFiles: [LargeFileItem] {
        let query = diskSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return diskLargeFiles }
        return diskLargeFiles.filter {
            "\($0.name) \($0.path)".lowercased().contains(query)
        }
    }

    var diskSelectedFiles: [LargeFileItem] {
        diskLargeFiles.filter(\.isSelected)
    }

    var diskSelectedBytes: Int64 {
        diskSelectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    func scanDisk(forceFolders: Bool = false) async {
        diskScanGeneration += 1
        let generation = diskScanGeneration
        let root = diskRootURL.standardizedFileURL
        let minSize = diskMinSize

        isDiskScanning = true
        diskLargeFiles = []
        diskFolderTask?.cancel()

        let cached = FolderSizeCache.load(root: root)
        diskFolders = cached?.folders ?? []

        let needsFolderScan = forceFolders || cached == nil || cached?.isFresh == false
        isDiskFolderScanning = needsFolderScan

        // Dung lượng thư mục: hiển thị dần từng thư mục khi đo xong.
        let folderTask: Task<Void, Never>? = needsFolderScan
            ? Task.detached(priority: .userInitiated) { [weak self] in
                let result = await DiskAnalyzer.folderUsage(of: root) { partial in
                    Task { @MainActor [weak self] in
                        guard let self,
                              generation == self.diskScanGeneration,
                              self.diskRootURL.standardizedFileURL == root else { return }
                        self.applyPartialFolder(partial)
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self, generation == self.diskScanGeneration else { return }
                    if !result.isEmpty {
                        self.diskFolders = result
                        FolderSizeCache.save(root: root, folders: result)
                    }
                    self.isDiskFolderScanning = false
                }
            }
            : nil
        diskFolderTask = folderTask

        // Danh sách tệp lớn: xong sau ~1 giây, không chờ đo dung lượng thư mục.
        let files = await Task.detached(priority: .userInitiated) {
            DiskAnalyzer.largeFiles(in: root, minSize: minSize)
        }.value

        guard generation == diskScanGeneration else { return }
        diskLargeFiles = files
        diskHasScanned = true
        diskStats = AppScanner.getDiskStats()
        isDiskScanning = false

        await folderTask?.value
    }

    private func applyPartialFolder(_ folder: FolderUsage) {
        if let index = diskFolders.firstIndex(where: { $0.id == folder.id }) {
            diskFolders[index] = folder
        } else {
            diskFolders.append(folder)
        }
        diskFolders.sort { $0.sizeBytes > $1.sizeBytes }
    }

    /// Chỉ quét lại danh sách tệp lớn, giữ nguyên dung lượng thư mục đang hiển thị.
    func rescanDiskFiles() async {
        diskScanGeneration += 1
        let generation = diskScanGeneration
        let root = diskRootURL.standardizedFileURL
        let minSize = diskMinSize

        isDiskScanning = true
        let files = await Task.detached(priority: .userInitiated) {
            DiskAnalyzer.largeFiles(in: root, minSize: minSize)
        }.value
        guard generation == diskScanGeneration else { return }

        diskLargeFiles = files
        diskStats = AppScanner.getDiskStats()
        isDiskScanning = false
    }

    func setDiskRoot(_ url: URL) async {
        diskRootURL = url.standardizedFileURL
        diskFolders = []
        diskLargeFiles = []
        diskSearchText = ""
        await scanDisk()
    }

    func goUpDiskFolder() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let current = diskRootURL.standardizedFileURL
        guard current.path != home.path else { return }

        let parent = current.deletingLastPathComponent().standardizedFileURL
        guard parent.path == home.path || parent.path.hasPrefix(home.path + "/") else { return }
        await setDiskRoot(parent)
    }

    func toggleDiskSelection(_ file: LargeFileItem) {
        guard let index = diskLargeFiles.firstIndex(where: { $0.id == file.id }) else { return }
        diskLargeFiles[index].isSelected.toggle()
    }

    func selectAllFilteredDiskFiles() {
        let ids = Set(filteredLargeFiles.map(\.id))
        for index in diskLargeFiles.indices where ids.contains(diskLargeFiles[index].id) {
            diskLargeFiles[index].isSelected = true
        }
    }

    func clearDiskSelection() {
        for index in diskLargeFiles.indices {
            diskLargeFiles[index].isSelected = false
        }
    }

    func trashSelectedDiskFiles() async {
        let targets = diskSelectedFiles
        guard !targets.isEmpty else { return }

        isRemoving = true
        defer { isRemoving = false }

        let result = await Task.detached(priority: .userInitiated) {
            await DiskAnalyzer.moveToTrash(targets)
        }.value

        let removedIDs = Set(targets.map(\.id).filter { !FileManager.default.fileExists(atPath: $0) })
        diskLargeFiles.removeAll { removedIDs.contains($0.id) }

        if result.movedCount > 0 {
            showBanner(
                "Đã chuyển \(result.movedCount) tệp (\(ByteFormat.string(from: result.freedBytes))) vào Thùng rác.",
                isError: !result.errors.isEmpty
            )
        } else {
            showBanner(result.errors.first ?? "Không thể chuyển các tệp đã chọn.", isError: true)
        }

        await scanDisk(forceFolders: true)
    }

    // MARK: - RAR → ZIP

    @Published var rarJobs: [RarJob] = []
    @Published var rarOutputMode: ConversionOutputMode = .sameFolder
    @Published var rarCustomOutputDirectory: URL?
    @Published var rarDeleteOriginal: Bool = false
    @Published var rarRevealInFinder: Bool = true
    @Published var rarPassword: String = ""
    @Published var isConvertingRAR: Bool = false

    private var rarTask: RarConversionTask?

    var rarPendingJobs: [RarJob] {
        rarJobs.filter { !$0.status.isFinished && !$0.status.isWorking }
    }

    var rarCompletedCount: Int {
        rarJobs.filter { $0.status.isFinished }.count
    }

    var rarSourceBytes: Int64 {
        rarJobs.reduce(0) { $0 + $1.sizeBytes }
    }

    var rarOutputBytes: Int64 {
        rarJobs.reduce(0) { partial, job in
            if case .done(_, let bytes) = job.status {
                return partial + bytes
            }
            return partial
        }
    }

    var rarOutputLabel: String {
        switch rarOutputMode {
        case .sameFolder: return "Lưu cùng thư mục gốc"
        case .downloads: return "Lưu vào Downloads"
        case .custom: return rarCustomOutputDirectory?.lastPathComponent ?? "Thư mục tuỳ chọn"
        }
    }

    func addRarFiles(_ urls: [URL]) {
        var rejected = 0
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !rarJobs.contains(where: { $0.id == standardized.path }) else { continue }
            guard RarConverter.isRarFile(standardized), RarConverter.isRarSignature(standardized) else {
                rejected += 1
                continue
            }
            let values = try? standardized.resourceValues(forKeys: [.fileSizeKey])
            rarJobs.append(
                RarJob(
                    id: standardized.path,
                    source: standardized,
                    name: standardized.lastPathComponent,
                    sizeBytes: Int64(values?.fileSize ?? 0)
                )
            )
        }

        if rejected > 0 {
            showBanner("Đã bỏ qua \(rejected) tệp không phải RAR hợp lệ.", isError: true)
        }
    }

    func removeRarJob(_ job: RarJob) {
        rarJobs.removeAll { $0.id == job.id }
    }

    func clearRarJobs() {
        guard !isConvertingRAR else { return }
        rarJobs.removeAll()
    }

    func setRarOutputDirectory(_ url: URL) {
        rarCustomOutputDirectory = url
        rarOutputMode = .custom
    }

    func cancelRarConversion() {
        rarTask?.cancel()
    }

    func convertRarJobs() async {
        guard !isConvertingRAR else { return }

        let indices = rarJobs.indices.filter {
            !rarJobs[$0].status.isFinished && !rarJobs[$0].status.isWorking
        }
        guard !indices.isEmpty else { return }

        isConvertingRAR = true
        let task = RarConversionTask()
        rarTask = task
        let password = rarPassword

        var outputs: [URL] = []
        var failures = 0

        for index in indices {
            if task.isCancelled { break }

            let job = rarJobs[index]
            let destination = resolvedRarDestination(for: job.source)
            rarJobs[index].status = .working(0)

            do {
                let outcome = try await Task.detached(priority: .userInitiated) { () throws -> RarConvertOutcome in
                    try RarConverter.convert(
                        source: job.source,
                        destination: destination,
                        password: password,
                        task: task
                    ) { progress in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let jobIndex = self.rarJobs.firstIndex(where: { $0.id == job.id }),
                                  self.rarJobs[jobIndex].status.isWorking else { return }
                            self.rarJobs[jobIndex].status = .working(progress)
                        }
                    }
                }.value

                if let jobIndex = rarJobs.firstIndex(where: { $0.id == job.id }) {
                    rarJobs[jobIndex].status = .done(output: outcome.outputURL, bytes: outcome.outputBytes)
                }
                outputs.append(outcome.outputURL)

                if rarDeleteOriginal {
                    try? FileManager.default.trashItem(at: job.source, resultingItemURL: nil)
                }
            } catch {
                failures += 1
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let jobIndex = rarJobs.firstIndex(where: { $0.id == job.id }) {
                    rarJobs[jobIndex].status = .failed(message)
                }
                if task.isCancelled { break }
            }
        }

        isConvertingRAR = false
        rarTask = nil

        if task.isCancelled {
            showBanner("Đã huỷ chuyển đổi RAR.", isError: true)
        } else if outputs.isEmpty {
            showBanner("Không chuyển được file nào. Kiểm tra mật khẩu hoặc định dạng RAR.", isError: true)
        } else {
            let suffix = failures > 0 ? " (\(failures) lỗi)" : ""
            showBanner("Đã chuyển \(outputs.count) file sang ZIP\(suffix).", isError: failures > 0)
        }

        if rarRevealInFinder, !outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }

    private func resolvedRarDestination(for source: URL) -> URL {
        let directory: URL
        switch rarOutputMode {
        case .sameFolder:
            directory = source.deletingLastPathComponent()
        case .downloads:
            directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        case .custom:
            directory = rarCustomOutputDirectory ?? source.deletingLastPathComponent()
        }
        return RarConverter.availableDestination(for: source, in: directory)
    }

    // MARK: - BAT → SH

    @Published var batJobs: [BatJob] = []
    @Published var selectedBatJobID: String?
    @Published var batOutputMode: ConversionOutputMode = .sameFolder
    @Published var batCustomOutputDirectory: URL?
    @Published var batMakeExecutable: Bool = true
    @Published var batRevealInFinder: Bool = true
    @Published var isSavingBAT: Bool = false

    var selectedBatJob: BatJob? {
        guard let selectedBatJobID else { return nil }
        return batJobs.first { $0.id == selectedBatJobID }
    }

    var batSavedCount: Int {
        batJobs.filter { $0.status.isSaved }.count
    }

    var batReadyCount: Int {
        batJobs.filter { $0.result != nil && !$0.status.isSaved }.count
    }

    var batIssueCount: Int {
        batJobs.reduce(0) { $0 + ($1.result?.warningCount ?? 0) }
    }

    var batOutputLabel: String {
        switch batOutputMode {
        case .sameFolder: return "Lưu cùng thư mục gốc"
        case .downloads: return "Lưu vào Downloads"
        case .custom: return batCustomOutputDirectory?.lastPathComponent ?? "Thư mục tuỳ chọn"
        }
    }

    func addBatFiles(_ urls: [URL]) {
        var rejected = 0

        for url in urls {
            let standardized = url.standardizedFileURL
            guard !batJobs.contains(where: { $0.id == standardized.path }) else { continue }

            let ext = standardized.pathExtension.lowercased()
            guard ext == "bat" || ext == "cmd" else {
                rejected += 1
                continue
            }

            let values = try? standardized.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)

            do {
                let result = try BatToShConverter.convert(contentsOf: standardized)
                batJobs.append(
                    BatJob(
                        id: standardized.path,
                        source: standardized,
                        name: standardized.lastPathComponent,
                        sizeBytes: size,
                        result: result,
                        status: .ready
                    )
                )
                if selectedBatJobID == nil {
                    selectedBatJobID = standardized.path
                }
            } catch {
                batJobs.append(
                    BatJob(
                        id: standardized.path,
                        source: standardized,
                        name: standardized.lastPathComponent,
                        sizeBytes: size,
                        result: nil,
                        status: .failed(error.localizedDescription)
                    )
                )
            }
        }

        if rejected > 0 {
            showBanner("Đã bỏ qua \(rejected) tệp không phải .bat/.cmd.", isError: true)
        }
    }

    func removeBatJob(_ job: BatJob) {
        batJobs.removeAll { $0.id == job.id }
        if selectedBatJobID == job.id {
            selectedBatJobID = batJobs.first?.id
        }
    }

    func clearBatJobs() {
        guard !isSavingBAT else { return }
        batJobs.removeAll()
        selectedBatJobID = nil
    }

    func setBatOutputDirectory(_ url: URL) {
        batCustomOutputDirectory = url
        batOutputMode = .custom
    }

    func saveBatScripts() async {
        guard !isSavingBAT else { return }
        let targets = batJobs.filter { $0.result != nil && !$0.status.isSaved }
        guard !targets.isEmpty else { return }

        isSavingBAT = true
        defer { isSavingBAT = false }

        var savedURLs: [URL] = []
        var failures = 0

        for job in targets {
            guard let result = job.result else { continue }
            let directory = resolvedBatDestinationDirectory(for: job.source)
            let destination = BatToShConverter.availableDestination(for: job.source, in: directory)

            do {
                try result.script.write(to: destination, atomically: true, encoding: .utf8)
                if batMakeExecutable {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: destination.path
                    )
                }
                if let index = batJobs.firstIndex(where: { $0.id == job.id }) {
                    batJobs[index].status = .saved(destination)
                }
                savedURLs.append(destination)
            } catch {
                failures += 1
                if let index = batJobs.firstIndex(where: { $0.id == job.id }) {
                    batJobs[index].status = .failed(error.localizedDescription)
                }
            }
        }

        if savedURLs.isEmpty {
            showBanner("Không lưu được file .sh nào.", isError: true)
        } else {
            let suffix = failures > 0 ? " (\(failures) lỗi)" : ""
            showBanner("Đã lưu \(savedURLs.count) file .sh\(suffix).", isError: failures > 0)
        }

        if batRevealInFinder, !savedURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
        }
    }

    private func resolvedBatDestinationDirectory(for source: URL) -> URL {
        switch batOutputMode {
        case .sameFolder:
            return source.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        case .custom:
            return batCustomOutputDirectory ?? source.deletingLastPathComponent()
        }
    }
}