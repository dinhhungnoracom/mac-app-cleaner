import AppKit
import Darwin
import Foundation
import MachO

final class SystemMonitorService {
    static let shared = SystemMonitorService()

    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousProcessTicks: [pid_t: (ticks: UInt64, time: Date)] = [:]
    private var hasPrimedProcessSamples = false
    private let timebaseNumer: Double
    private let timebaseDenom: Double

    private init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        timebaseNumer = Double(timebase.numer)
        timebaseDenom = Double(timebase.denom)
    }

    func getCPUMetrics() -> SystemCPUMetrics {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuLoad = host_cpu_load_info()
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard kr == KERN_SUCCESS else {
            return SystemCPUMetrics(userPercent: 0, systemPercent: 0, idlePercent: 100, totalUsagePercent: 0)
        }

        let user = UInt64(cpuLoad.cpu_ticks.0)
        let system = UInt64(cpuLoad.cpu_ticks.1)
        let idle = UInt64(cpuLoad.cpu_ticks.2)
        let nice = UInt64(cpuLoad.cpu_ticks.3)

        guard let prev = previousCPUTicks else {
            previousCPUTicks = (user, system, idle, nice)
            return SystemCPUMetrics(userPercent: 5.0, systemPercent: 5.0, idlePercent: 90.0, totalUsagePercent: 10.0)
        }

        let deltaUser = user >= prev.user ? user - prev.user : 0
        let deltaSystem = system >= prev.system ? system - prev.system : 0
        let deltaIdle = idle >= prev.idle ? idle - prev.idle : 0
        let deltaNice = nice >= prev.nice ? nice - prev.nice : 0
        let totalTicks = deltaUser + deltaSystem + deltaIdle + deltaNice

        previousCPUTicks = (user, system, idle, nice)

        guard totalTicks > 0 else {
            return SystemCPUMetrics(userPercent: 0, systemPercent: 0, idlePercent: 100, totalUsagePercent: 0)
        }

        let uPct = (Double(deltaUser) / Double(totalTicks)) * 100.0
        let sPct = (Double(deltaSystem) / Double(totalTicks)) * 100.0
        let iPct = (Double(deltaIdle) / Double(totalTicks)) * 100.0
        let usage = min(100.0, max(0.0, 100.0 - iPct))

        return SystemCPUMetrics(
            userPercent: uPct,
            systemPercent: sPct,
            idlePercent: iPct,
            totalUsagePercent: usage
        )
    }

    func getMemoryMetrics() -> SystemMemoryMetrics {
        var memSize: UInt64 = 0
        var memSizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memSizeLen, nil, 0)

        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &size)
            }
        }

        guard kr == KERN_SUCCESS else {
            return SystemMemoryMetrics(totalBytes: memSize, usedBytes: 0, freeBytes: memSize, activeBytes: 0, wiredBytes: 0, compressedBytes: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStat.active_count) * pageSize
        let wired = UInt64(vmStat.wire_count) * pageSize
        let compressed = UInt64(vmStat.compressor_page_count) * pageSize
        let used = min(memSize, active + wired + compressed)
        let free = memSize > used ? memSize - used : 0

        return SystemMemoryMetrics(
            totalBytes: memSize,
            usedBytes: used,
            freeBytes: free,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed
        )
    }

    /// Đọc danh sách tiến trình trực tiếp qua libproc (nhanh hơn gọi `ps` ~10x
    /// và không bị treo khi output vượt bộ đệm pipe).
    func getProcesses() -> [ProcessItem] {
        // Lần đầu chưa có mốc thời gian để tính %CPU: lấy mẫu 2 lần cách nhau 250ms.
        if !hasPrimedProcessSamples {
            _ = sampleProcesses()
            hasPrimedProcessSamples = true
            Thread.sleep(forTimeInterval: 0.25)
        }
        return sampleProcesses()
    }

    private func sampleProcesses() -> [ProcessItem] {
        let runningApps = NSWorkspace.shared.runningApplications
        var appByPID: [pid_t: NSRunningApplication] = [:]
        appByPID.reserveCapacity(runningApps.count)
        for app in runningApps {
            appByPID[app.processIdentifier] = app
        }

        var capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        if capacity <= 0 { capacity = Int32(MemoryLayout<pid_t>.size) * 1024 }
        var pids = [pid_t](repeating: 0, count: max(1024, Int(capacity) / MemoryLayout<pid_t>.size))
        let used = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        let count = max(0, Int(used) / MemoryLayout<pid_t>.size)
        guard count > 0 else { return [] }

        let now = Date()
        var nextSamples: [pid_t: (ticks: UInt64, time: Date)] = [:]
        nextSamples.reserveCapacity(count)
        var items: [ProcessItem] = []
        items.reserveCapacity(count)

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let read = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_taskinfo>.size)
            )
            guard read == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let ticks = info.pti_total_user &+ info.pti_total_system
            var cpuPercent = 0.0
            if let previous = previousProcessTicks[pid], ticks >= previous.ticks {
                let elapsed = now.timeIntervalSince(previous.time)
                if elapsed > 0.05 {
                    let deltaNanoseconds = Double(ticks - previous.ticks) * timebaseNumer / timebaseDenom
                    cpuPercent = max(0, deltaNanoseconds / 1_000_000_000.0 / elapsed * 100.0)
                }
            }
            nextSamples[pid] = (ticks, now)

            let memoryBytes = Int64(info.pti_resident_size)
            let app = appByPID[pid]
            let identity = processIdentity(pid: pid, app: app)

            items.append(
                ProcessItem(
                    id: pid,
                    pid: pid,
                    name: identity.name,
                    cpuPercent: cpuPercent,
                    memoryBytes: memoryBytes,
                    executablePath: identity.path,
                    appURL: identity.appURL,
                    isGUIApp: app != nil,
                    bundleID: app?.bundleIdentifier
                )
            )
        }

        previousProcessTicks = nextSamples
        return items
    }

    private func processIdentity(
        pid: pid_t,
        app: NSRunningApplication?
    ) -> (name: String, path: String, appURL: URL?) {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? (String(validatingUTF8: pathBuffer) ?? "") : ""

        if let app {
            let name = app.localizedName
                ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? (path as NSString).lastPathComponent
            return (name, path.isEmpty ? (app.bundleURL?.path ?? "") : path, app.bundleURL)
        }

        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        var name = nameLength > 0 ? (String(validatingUTF8: nameBuffer) ?? "") : ""
        if name.isEmpty {
            name = (path as NSString).lastPathComponent
        }

        var appURL: URL?
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.upperBound].dropLast())
            appURL = URL(fileURLWithPath: appPath)
            let parentName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            if !name.hasPrefix(parentName) {
                name = "\(parentName) (\(name))"
            }
        } else if path.hasSuffix(".app") || path.contains(".app/Contents/MacOS/") {
            appURL = URL(fileURLWithPath: path)
        }

        if name.isEmpty { name = "PID \(pid)" }
        return (name, path, appURL)
    }

    func terminateProcess(pid: pid_t, force: Bool) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if force {
                _ = app.forceTerminate()
            } else {
                _ = app.terminate()
            }
        }

        let sig = force ? SIGKILL : SIGTERM
        let res = kill(pid, sig)
        return res == 0
    }
}
