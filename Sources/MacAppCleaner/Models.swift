import AppKit
import Foundation

enum AppSource: String, CaseIterable {
    case direct = "Direct"
    case appStore = "App Store"
    case homebrew = "Homebrew"
    case system = "macOS System"
}

enum CpuArch: String {
    case appleSilicon = "Apple Silicon"
    case universal = "Universal"
    case intel = "Intel"
    case unknown = "Script / Khác"
}

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let folderName: String
    let url: URL
    let locationLabel: String
    let bundleID: String
    let version: String
    let sizeBytes: Int64
    let lastUsedDate: Date?
    let dateAdded: Date?
    let source: AppSource
    let brewToken: String?
    let arch: CpuArch
    let isSystem: Bool
    let isProtected: Bool
    let isRunning: Bool

    var path: String { url.path }

    var daysUnused: Int? {
        guard let lastUsedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastUsedDate, to: Date()).day
    }

    var isUnused90Days: Bool {
        guard !isSystem else { return false }
        if let days = daysUnused {
            return days >= 90
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.url == rhs.url
    }
}

struct LeftoverItem: Identifiable, Hashable {
    let id: String
    let category: String
    let name: String
    let url: URL
    let sizeBytes: Int64
    var isSelected: Bool = true

    var path: String { url.path }
}

enum MainTab: String, CaseIterable, Identifiable {
    case apps = "Ứng dụng"
    case trash = "Thùng rác"
    case monitor = "Giám sát"

    var id: String { rawValue }
}

struct SystemCPUMetrics {
    let userPercent: Double
    let systemPercent: Double
    let idlePercent: Double
    let totalUsagePercent: Double
}

struct SystemMemoryMetrics {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let activeBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }
}

struct ProcessItem: Identifiable, Hashable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let executablePath: String
    let appURL: URL?
    let isGUIApp: Bool
    let bundleID: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.pid == rhs.pid
    }
}

enum ProcessFilter: String, CaseIterable, Identifiable {
    case appsOnly = "Chỉ ứng dụng"
    case all = "Tất cả tiến trình"

    var id: String { rawValue }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpuDesc = "CPU: Cao nhất"
    case memoryDesc = "RAM: Nhiều nhất"
    case nameAsc = "Tên: A → Z"

    var id: String { rawValue }
}

enum TrashSort: String, CaseIterable, Identifiable {
    case sizeDesc = "Dung lượng: Lớn nhất"
    case newestDesc = "Mới bỏ vào nhất"
    case nameAsc = "Tên: A → Z"

    var id: String { rawValue }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case thirdParty = "Cài thêm"
    case large = "Nặng (≥ 500 MB)"
    case unused = "Lâu chưa dùng"
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case all = "Tất cả (gồm macOS)"

    var id: String { rawValue }
}

enum AppSort: String, CaseIterable, Identifiable {
    case sizeDesc = "Dung lượng: Lớn nhất"
    case unusedDesc = "Lâu chưa dùng nhất"
    case nameAsc = "Tên: A → Z"
    case addedDesc = "Mới cài gần đây"

    var id: String { rawValue }
}

struct DiskStats {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        return f
    }()

    static func string(from bytes: Int64) -> String {
        formatter.string(fromByteCount: max(0, bytes))
    }
}
