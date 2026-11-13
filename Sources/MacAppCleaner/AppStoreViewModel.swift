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

    @Published var isRemoving: Bool = false
    @Published var statusBanner: (message: String, isError: Bool)?

    private var iconCache: [String: NSImage] = [:]

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
}
