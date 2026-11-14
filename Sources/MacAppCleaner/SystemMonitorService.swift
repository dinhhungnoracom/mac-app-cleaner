import AppKit
import Foundation
import MachO

final class SystemMonitorService {
    static let shared = SystemMonitorService()

    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    private init() {}

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

    func getProcesses() -> [ProcessItem] {
        let runningApps = NSWorkspace.shared.runningApplications
        var appByPID: [pid_t: NSRunningApplication] = [:]
        for app in runningApps {
            appByPID[app.processIdentifier] = app
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,%cpu,rss,comm", "-r"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var items: [ProcessItem] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pidInt = Int32(parts[0]),
                  let cpuDouble = Double(parts[1]),
                  let rssKb = Int64(parts[2]) else {
                continue
            }

            let execPath = String(parts[3])
            let memBytes = rssKb * 1024

            if let app = appByPID[pidInt] {
                let appName = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? (execPath as NSString).lastPathComponent
                items.append(ProcessItem(
                    id: pidInt,
                    pid: pidInt,
                    name: appName,
                    cpuPercent: cpuDouble,
                    memoryBytes: memBytes,
                    executablePath: execPath,
                    appURL: app.bundleURL,
                    isGUIApp: true,
                    bundleID: app.bundleIdentifier
                ))
            } else {
                // Check if process belongs inside an .app bundle (e.g. Helper processes)
                var enclosingAppURL: URL? = nil
                var friendlyName = (execPath as NSString).lastPathComponent

                if let appRange = execPath.range(of: ".app/") {
                    let appPath = String(execPath[..<appRange.upperBound].dropLast())
                    enclosingAppURL = URL(fileURLWithPath: appPath)
                    let parentAppName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                    friendlyName = "\(parentAppName) (\(friendlyName))"
                }

                items.append(ProcessItem(
                    id: pidInt,
                    pid: pidInt,
                    name: friendlyName,
                    cpuPercent: cpuDouble,
                    memoryBytes: memBytes,
                    executablePath: execPath,
                    appURL: enclosingAppURL,
                    isGUIApp: false,
                    bundleID: nil
                ))
            }
        }

        return items
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
