import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var showSingleConfirm = false
    @State private var showBulkConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            switch vm.activeTab {
            case .apps:
                statsStrip
                Divider()
                toolbar
                if vm.isBulkMode {
                    bulkActionBar
                }
                Divider()

                HSplitView {
                    appListPane
                        .frame(minWidth: 440, idealWidth: 560)

                    inspectorPane
                        .frame(minWidth: 360, idealWidth: 430)
                }
            case .cleanup:
                CleanupView(vm: vm)
            case .disk:
                DiskAnalyzerView(vm: vm)
            case .trash:
                TrashView(vm: vm)
            case .monitor:
                ActivityMonitorView(vm: vm)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let banner = vm.statusBanner {
                Text(banner.message)
                    .font(.callout.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(banner.isError ? Color.red.opacity(0.92) : Color.green.opacity(0.9))
                    .cornerRadius(10)
                    .shadow(radius: 8)
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if vm.apps.isEmpty {
                await vm.refresh()
            }
        }
        .onChange(of: vm.activeTab) { tab in
            if tab == .trash {
                Task { await vm.refreshTrash() }
            }
            if tab == .monitor {
                vm.startMonitorTimer()
            } else {
                vm.stopMonitorTimer()
            }
        }
        .alert("Chuyển \"\(vm.selectedApp?.name ?? "")\" vào Thùng rác?", isPresented: $showSingleConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Chuyển vào Thùng rác", role: .destructive) {
                Task { await vm.removeSelectedApp() }
            }
        } message: {
            let count = vm.leftovers.filter(\.isSelected).count
            Text(
                "Ứng dụng và \(count) mục file rác đã chọn (tổng \(ByteFormat.string(from: vm.selectedReclaimBytes))) sẽ được chuyển vào Thùng rác. Bạn vẫn có thể khôi phục từ Thùng rác."
            )
        }
        .alert("Gỡ \(vm.bulkSelectedApps.count) ứng dụng đã chọn?", isPresented: $showBulkConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Chuyển tất cả vào Thùng rác", role: .destructive) {
                Task { await vm.removeBulkSelectedApps() }
            }
        } message: {
            Text(
                "Các ứng dụng đã chọn (ước tính tối thiểu \(ByteFormat.string(from: vm.bulkTotalBytes))) cùng file liên quan trong ~/Library sẽ được chuyển vào Thùng rác."
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 26))
                .foregroundStyle(.blue, .cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac App Cleaner")
                    .font(.title3.bold())
                Text("Quét app, dọn rác & làm sạch Thùng rác")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 232, alignment: .leading)

            tabBar

            Spacer()

            if let disk = vm.diskStats {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Ổ đĩa Mac: Trống \(ByteFormat.string(from: disk.availableBytes)) / \(ByteFormat.string(from: disk.totalBytes))")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 188, alignment: .trailing)
                    ProgressView(value: disk.usedFraction)
                        .frame(width: 140)
                }
            }

            Button {
                Task {
                    switch vm.activeTab {
                    case .apps:
                        await vm.refresh()
                    case .cleanup:
                        await vm.scanJunk()
                    case .disk:
                        await vm.scanDisk()
                    case .trash:
                        await vm.refreshTrash()
                    case .monitor:
                        await vm.refreshMonitor()
                    }
                }
            } label: {
                if vm.isScanning || vm.isScanningTrash || vm.isRefreshingMonitor {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang tải...")
                            .lineLimit(1)
                            .fixedSize()
                    }
                } else {
                    Label("Cập nhật", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning || vm.isScanningTrash || vm.isRefreshingMonitor || vm.isRemoving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Ứng dụng cài thêm",
                value: "\(vm.thirdPartyApps.count)",
                subtitle: "Tổng (gồm macOS): \(vm.apps.count)",
                accent: .primary
            )
            StatCard(
                title: "Tổng dung lượng App",
                value: ByteFormat.string(from: vm.thirdPartyTotalBytes),
                subtitle: "Chưa tính cache trong ~/Library",
                accent: .blue
            )
            StatCard(
                title: "Ít dùng (≥ 90 ngày)",
                value: "\(vm.unused90Count)",
                subtitle: "Hoặc chưa từng mở",
                accent: .orange
            )
            StatCard(
                title: "Đang hiển thị",
                value: "\(vm.filteredApps.count)",
                subtitle: ByteFormat.string(from: vm.filteredApps.reduce(0) { $0 + $1.sizeBytes }),
                accent: .green
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm theo tên app, bundle ID, đường dẫn...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
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
            .frame(maxWidth: 280)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AppFilter.allCases) { f in
                        Button(f.rawValue) {
                            vm.filter = f
                        }
                        .buttonStyle(.bordered)
                        .tint(vm.filter == f ? .blue : .secondary)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()

            Picker("Sắp xếp", selection: $vm.sort) {
                ForEach(AppSort.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            Toggle(isOn: $vm.isBulkMode) {
                Label("Chọn nhiều", systemImage: "checklist")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .onChange(of: vm.isBulkMode) { enabled in
                if !enabled {
                    vm.clearBulkSelection()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    vm.activeTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.callout.weight(vm.activeTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if tab == .trash, !vm.trashItems.isEmpty {
                            Text("\(vm.trashItems.count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(vm.activeTab == tab ? 0.85 : 0.14))
                                .foregroundColor(vm.activeTab == tab ? .white : .red)
                                .cornerRadius(999)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .foregroundColor(vm.activeTab == tab ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(vm.activeTab == tab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(MainTab.allCases.firstIndex(of: tab).map { $0 + 1 } ?? 1))")
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.16)))
    }

    private var bulkActionBar: some View {
        HStack {
            Button("Chọn tất cả đang lọc") {
                vm.selectAllFilteredForBulk()
            }
            .controlSize(.small)

            Button("Bỏ chọn") {
                vm.clearBulkSelection()
            }
            .controlSize(.small)

            Text("Đã chọn \(vm.bulkSelectedApps.count) ứng dụng (\(ByteFormat.string(from: vm.bulkTotalBytes)))")
                .font(.callout.weight(.medium))

            Spacer()

            Button(role: .destructive) {
                showBulkConfirm = true
            } label: {
                Label("Chuyển vào Thùng rác", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.bulkSelectedApps.isEmpty || vm.isRemoving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
    }

    private var appListPane: some View {
        Group {
            if vm.isScanning && vm.apps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang quét ứng dụng trên MacBook...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("Không có ứng dụng nào khớp bộ lọc.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSize = max(vm.filteredApps.map(\.sizeBytes).max() ?? 1, 1)
                List(vm.filteredApps) { app in
                    AppRowView(
                        app: app,
                        icon: vm.icon(for: app),
                        maxSizeBytes: maxSize,
                        isSelected: vm.selectedAppID == app.id,
                        isBulkMode: vm.isBulkMode,
                        isBulkChecked: vm.bulkSelectedIDs.contains(app.id),
                        onToggleBulk: { vm.toggleBulkSelection(for: app) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await vm.selectApp(app) }
                    }
                    .listRowBackground(
                        vm.selectedAppID == app.id
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
                }
                .listStyle(.inset)
            }
        }
    }

    private var inspectorPane: some View {
        Group {
            if let app = vm.selectedApp {
                VStack(spacing: 0) {
                    // App Header
                    HStack(spacing: 12) {
                        Image(nsImage: vm.icon(for: app))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(app.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                if app.isRunning {
                                    BadgeView(text: "Đang chạy", color: .green)
                                }
                                if app.isProtected {
                                    BadgeView(text: "Hệ thống", color: .red)
                                }
                            }
                            Text(app.bundleID.isEmpty ? "(Không có Bundle ID)" : app.bundleID)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                BadgeView(text: app.source.rawValue, color: sourceColor(app.source))
                                BadgeView(text: app.locationLabel, color: .secondary)
                                if let brew = app.brewToken {
                                    BadgeView(text: "brew: \(brew)", color: .orange)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(14)

                    Divider()

                    // Metadata Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        MetaTile(label: "Dung lượng App", value: ByteFormat.string(from: app.sizeBytes))
                        MetaTile(label: "Phiên bản", value: app.version)
                        MetaTile(label: "Kiến trúc", value: app.arch.rawValue)
                        MetaTile(label: "Lần cuối mở", value: lastUsedLabel(for: app))
                    }
                    .padding(12)

                    // Path + quick actions
                    HStack {
                        Text(app.path)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            AppRemover.revealInFinder(app.url)
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .controlSize(.small)

                        if app.isRunning {
                            Button {
                                vm.quitSelectedApp()
                            } label: {
                                Label("Thoát", systemImage: "stop.circle")
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                    Divider()

                    // Leftovers Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("File liên quan trong ~/Library")
                                    .font(.subheadline.weight(.semibold))
                                if vm.isLoadingLeftovers {
                                    Text("Đang quét Caches, Application Support, Preferences...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if vm.leftovers.isEmpty {
                                    Text("Không tìm thấy file rác liên quan.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    let total = vm.leftovers.reduce(0) { $0 + $1.sizeBytes }
                                    Text("\(vm.leftovers.count) mục (\(ByteFormat.string(from: total)))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if !vm.leftovers.isEmpty {
                                Button("Chọn / Bỏ hết") {
                                    vm.toggleAllLeftovers()
                                }
                                .controlSize(.small)
                            }
                        }

                        if vm.isLoadingLeftovers {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Đang tìm file rác...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List($vm.leftovers) { $item in
                                HStack(alignment: .top, spacing: 8) {
                                    Toggle("", isOn: $item.isSelected)
                                        .labelsHidden()
                                        .disabled(app.isProtected)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(item.category) — \(item.name)")
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(item.path)
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Text(ByteFormat.string(from: item.sizeBytes))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                    .padding(12)

                    Divider()

                    // Footer Action
                    VStack(spacing: 8) {
                        HStack {
                            Text("Tổng dung lượng sẽ giải phóng:")
                                .font(.callout)
                            Spacer()
                            Text(ByteFormat.string(from: vm.selectedReclaimBytes))
                                .font(.title3.bold())
                                .foregroundColor(.green)
                        }

                        Button(role: .destructive) {
                            showSingleConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                if vm.isRemoving {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Chuyển vào Thùng rác", systemImage: "trash")
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(app.isProtected || vm.isRemoving)

                        if app.isProtected {
                            Text("Ứng dụng hệ thống macOS được bảo vệ để tránh hỏng hệ điều hành.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Chọn một ứng dụng")
                        .font(.headline)
                    Text("Nhấn vào ứng dụng bên trái để xem chi tiết, quét file rác trong ~/Library và chuyển vào Thùng rác an toàn.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sourceColor(_ source: AppSource) -> Color {
        switch source {
        case .homebrew: return .orange
        case .appStore: return .blue
        case .system: return .red
        case .direct: return .secondary
        }
    }

    private func lastUsedLabel(for app: InstalledApp) -> String {
        guard let days = app.daysUnused else { return "Chưa có dữ liệu" }
        if days == 0 { return "Hôm nay" }
        if days == 1 { return "Hôm qua" }
        if days < 30 { return "\(days) ngày trước" }
        let months = days / 30
        if months < 12 { return "\(months) tháng trước" }
        return "\(months / 12) năm trước"
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundColor(accent)
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

private struct MetaTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundColor(color == .secondary ? .secondary : color)
            .cornerRadius(999)
    }
}

private struct AppRowView: View {
    let app: InstalledApp
    let icon: NSImage
    let maxSizeBytes: Int64
    let isSelected: Bool
    let isBulkMode: Bool
    let isBulkChecked: Bool
    let onToggleBulk: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if isBulkMode {
                Button(action: onToggleBulk) {
                    Image(systemName: isBulkChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundColor(app.isProtected ? .secondary.opacity(0.4) : (isBulkChecked ? .accentColor : .secondary))
                }
                .buttonStyle(.plain)
                .disabled(app.isProtected)
            }

            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if app.source != .direct {
                        BadgeView(
                            text: app.source == .system ? "macOS" : app.source.rawValue,
                            color: app.source == .homebrew ? .orange : (app.source == .appStore ? .blue : .red)
                        )
                    }
                    if app.isRunning {
                        BadgeView(text: "Đang chạy", color: .green)
                    }
                    if app.isUnused90Days {
                        BadgeView(text: "Ít dùng", color: .orange)
                    }
                }

                HStack(spacing: 6) {
                    Text("v\(app.version)")
                    Text("•")
                    Text(app.arch.rawValue)
                    Text("•")
                    Text(lastUsedShort)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormat.string(from: app.sizeBytes))
                    .font(.callout.weight(.semibold))
                let ratio = max(0.04, min(1.0, Double(app.sizeBytes) / Double(maxSizeBytes)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(app.sizeBytes >= 500 * 1024 * 1024 ? Color.orange : Color.accentColor)
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(width: 82, height: 4)
            }
        }
        .padding(.vertical, 4)
    }

    private var lastUsedShort: String {
        guard let days = app.daysUnused else { return "Chưa có dữ liệu" }
        if days == 0 { return "Hôm nay" }
        if days == 1 { return "Hôm qua" }
        if days < 30 { return "\(days) ngày trước" }
        return "\(days / 30) tháng trước"
    }
}
