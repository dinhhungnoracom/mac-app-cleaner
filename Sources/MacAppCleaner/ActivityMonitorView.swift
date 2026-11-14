import SwiftUI

struct ActivityMonitorView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var targetProcessForQuit: ProcessItem?
    @State private var targetProcessForForceQuit: ProcessItem?

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider()
            monitorToolbar
            Divider()
            processListContent
        }
        .onAppear {
            vm.startMonitorTimer()
        }
        .onDisappear {
            vm.stopMonitorTimer()
        }
        .confirmationDialog(
            "Thoát tiến trình \"\(targetProcessForQuit?.name ?? "")\" (PID \(targetProcessForQuit?.pid ?? 0))?",
            isPresented: Binding(
                get: { targetProcessForQuit != nil },
                set: { if !$0 { targetProcessForQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Thoát (Graceful)", role: .none) {
                if let proc = targetProcessForQuit {
                    Task { await vm.terminateProcess(proc, force: false) }
                }
            }
            Button("Buộc dừng (Force Quit)", role: .destructive) {
                if let proc = targetProcessForQuit {
                    Task { await vm.terminateProcess(proc, force: true) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Tiến trình sẽ nhận tín hiệu đóng. Mọi dữ liệu chưa lưu trong ứng dụng này có thể bị mất.")
        }
        .confirmationDialog(
            "Buộc dừng ngay lập tức \"\(targetProcessForForceQuit?.name ?? "")\" (PID \(targetProcessForForceQuit?.pid ?? 0))?",
            isPresented: Binding(
                get: { targetProcessForForceQuit != nil },
                set: { if !$0 { targetProcessForForceQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Buộc dừng ngay (SIGKILL)", role: .destructive) {
                if let proc = targetProcessForForceQuit {
                    Task { await vm.terminateProcess(proc, force: true) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Lệnh này gửi trực tiếp tín hiệu SIGKILL để đóng tiến trình ngay lập tức mà không đợi phản hồi.")
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            // CPU Card
            if let cpu = vm.cpuMetrics {
                let usage = cpu.totalUsagePercent
                MetricCard(
                    title: "CPU Hệ thống",
                    value: String(format: "%.1f%%", usage),
                    subtitle: String(format: "User: %.1f%% • System: %.1f%%", cpu.userPercent, cpu.systemPercent),
                    fraction: usage / 100.0,
                    accentColor: cpuColor(usage)
                )
            } else {
                MetricCard(
                    title: "CPU Hệ thống",
                    value: "—",
                    subtitle: "Đang đo lường...",
                    fraction: 0,
                    accentColor: .blue
                )
            }

            // RAM Card
            if let mem = vm.memoryMetrics {
                let usedStr = ByteFormat.string(from: Int64(mem.usedBytes))
                let totalStr = ByteFormat.string(from: Int64(mem.totalBytes))
                MetricCard(
                    title: "Bộ nhớ RAM",
                    value: "\(usedStr) / \(totalStr)",
                    subtitle: String(format: "Trống: %@ • Nén: %@",
                                    ByteFormat.string(from: Int64(mem.freeBytes)),
                                    ByteFormat.string(from: Int64(mem.compressedBytes))),
                    fraction: mem.usedFraction,
                    accentColor: mem.usedFraction > 0.85 ? .red : (mem.usedFraction > 0.7 ? .orange : .blue)
                )
            } else {
                MetricCard(
                    title: "Bộ nhớ RAM",
                    value: "—",
                    subtitle: "Đang đọc Mach VM...",
                    fraction: 0,
                    accentColor: .blue
                )
            }

            // Disk Card
            if let disk = vm.diskStats {
                let avail = ByteFormat.string(from: disk.availableBytes)
                let total = ByteFormat.string(from: disk.totalBytes)
                MetricCard(
                    title: "Ổ đĩa Khởi động",
                    value: "Trống \(avail)",
                    subtitle: "Tổng dung lượng: \(total)",
                    fraction: disk.usedFraction,
                    accentColor: disk.usedFraction > 0.9 ? .red : .teal
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var monitorToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm tiến trình, tên app, PID...", text: $vm.processSearchText)
                    .textFieldStyle(.plain)
                if !vm.processSearchText.isEmpty {
                    Button {
                        vm.processSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
            .frame(maxWidth: 260)

            Picker("Phạm vi", selection: $vm.processFilter) {
                ForEach(ProcessFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)

            Picker("Sắp xếp", selection: $vm.processSort) {
                ForEach(ProcessSort.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Tự cập nhật 2s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            Button {
                Task { await vm.refreshMonitor() }
            } label: {
                if vm.isRefreshingMonitor {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Cập nhật", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(vm.isRefreshingMonitor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var processListContent: some View {
        if vm.processes.isEmpty && vm.isRefreshingMonitor {
            VStack(spacing: 12) {
                ProgressView()
                Text("Đang đọc danh sách tiến trình...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filteredProcesses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Không tìm thấy tiến trình nào khớp bộ lọc.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let list = vm.filteredProcesses
            let maxMem = max(list.map(\.memoryBytes).max() ?? 1, 1)

            VStack(spacing: 0) {
                // Table header
                HStack(spacing: 12) {
                    Text("TIẾN TRÌNH / ỨNG DỤNG")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 38)

                    Text("PID")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)

                    Text("% CPU")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    Text("RAM")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Text("THAO TÁC")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 150, alignment: .center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

                Divider()

                List(list) { item in
                    ProcessRowView(
                        item: item,
                        icon: vm.iconForProcess(item),
                        maxMemBytes: maxMem,
                        onQuit: {
                            targetProcessForQuit = item
                        },
                        onForceQuit: {
                            targetProcessForForceQuit = item
                        }
                    )
                }
                .listStyle(.inset)
            }
        }
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 45 { return .orange }
        return .green
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let fraction: Double
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.callout.bold())
                    .foregroundColor(accentColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(4, geo.size.width * min(1.0, max(0.0, fraction))))
                }
            }
            .frame(height: 6)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
    }
}

private struct ProcessRowView: View {
    let item: ProcessItem
    let icon: NSImage
    let maxMemBytes: Int64
    let onQuit: () -> Void
    let onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if item.isGUIApp {
                        Text("App")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                Text(item.executablePath)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // PID
            Text(String(item.pid))
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            // CPU %
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", item.cpuPercent))
                    .font(.callout.weight(.semibold))
                    .foregroundColor(item.cpuPercent > 50 ? .red : (item.cpuPercent > 20 ? .orange : .primary))

                let cpuRatio = min(1.0, max(0.04, item.cpuPercent / 100.0))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(item.cpuPercent > 50 ? Color.red : (item.cpuPercent > 20 ? Color.orange : Color.green))
                            .frame(width: geo.size.width * cpuRatio)
                    }
                }
                .frame(width: 64, height: 3)
            }
            .frame(width: 90, alignment: .trailing)

            // Memory RAM
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(from: item.memoryBytes))
                    .font(.callout.weight(.semibold))

                let memRatio = min(1.0, max(0.04, Double(item.memoryBytes) / Double(maxMemBytes)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * memRatio)
                    }
                }
                .frame(width: 64, height: 3)
            }
            .frame(width: 100, alignment: .trailing)

            // Actions
            HStack(spacing: 6) {
                Button("Thoát", action: onQuit)
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                Button(action: onForceQuit) {
                    Image(systemName: "xmark.octagon")
                        .foregroundColor(.red)
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .help("Buộc dừng (Force Quit)")
            }
            .frame(width: 150, alignment: .center)
        }
        .padding(.vertical, 3)
    }
}
