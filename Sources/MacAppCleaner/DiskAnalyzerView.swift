import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var showTrashConfirm = false

    private static let minSizeOptions: [(String, Int64)] = [
        ("≥ 50 MB", 50 * 1024 * 1024),
        ("≥ 100 MB", 100 * 1024 * 1024),
        ("≥ 500 MB", 500 * 1024 * 1024),
        ("≥ 1 GB", 1024 * 1024 * 1024)
    ]

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        df.locale = Locale(identifier: "vi_VN")
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            statsStrip
            Divider()
            toolbar
            Divider()
            HSplitView {
                folderPane
                    .frame(minWidth: 300, idealWidth: 340)
                filePane
                    .frame(minWidth: 480)
            }
        }
        .onAppear {
            if !vm.diskHasScanned && !vm.isDiskScanning {
                Task { await vm.scanDisk() }
            }
        }
        .alert(
            "Chuyển \(vm.diskSelectedFiles.count) tệp vào Thùng rác?",
            isPresented: $showTrashConfirm
        ) {
            Button("Huỷ", role: .cancel) {}
            Button("Chuyển vào Thùng rác", role: .destructive) {
                Task { await vm.trashSelectedDiskFiles() }
            }
        } message: {
            Text(
                "\(ByteFormat.string(from: vm.diskSelectedBytes)) sẽ được chuyển vào Thùng rác macOS. Bạn có thể khôi phục từ Thùng rác nếu chọn nhầm."
            )
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            if let disk = vm.diskStats {
                DiskStatCard(
                    title: "Ổ đĩa Mac",
                    value: "Trống \(ByteFormat.string(from: disk.availableBytes))",
                    subtitle: "Tổng \(ByteFormat.string(from: disk.totalBytes)) • đã dùng \(ByteFormat.string(from: disk.usedBytes))",
                    accent: disk.usedFraction > 0.9 ? .red : .primary
                )
            } else {
                DiskStatCard(
                    title: "Ổ đĩa Mac",
                    value: "—",
                    subtitle: "Chưa đọc được thông tin ổ đĩa",
                    accent: .secondary
                )
            }

            DiskStatCard(
                title: "Phạm vi đang xem",
                value: vm.diskRootLabel,
                subtitle: vm.diskRootURL.path,
                accent: .blue
            )

            DiskStatCard(
                title: "Thư mục lớn nhất",
                value: ByteFormat.string(from: vm.diskFoldersTotalBytes),
                subtitle: "\(vm.diskFolders.count) thư mục con trực tiếp",
                accent: .purple
            )

            DiskStatCard(
                title: "Tệp lớn",
                value: "\(vm.diskLargeFiles.count)",
                subtitle: "Tổng \(ByteFormat.string(from: vm.diskLargeFiles.reduce(0) { $0 + $1.sizeBytes }))",
                accent: .orange
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(DiskScope.allCases) { scope in
                    Button(scope.title) {
                        Task { await vm.setDiskRoot(scope.url) }
                    }
                }
                Divider()
                Button("Chọn thư mục…") { chooseFolder() }
            } label: {
                Label(vm.diskRootLabel, systemImage: "folder")
            }
            .frame(width: 170)

            Button {
                Task { await vm.goUpDiskFolder() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .help("Lên thư mục cha")
            .disabled(!vm.diskCanGoUp || vm.isDiskScanning)

            Picker("Kích thước", selection: $vm.diskMinSize) {
                ForEach(Self.minSizeOptions, id: \.1) { option in
                    Text(option.0).tag(option.1)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: vm.diskMinSize) { _ in
                Task { await vm.rescanDiskFiles() }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Lọc theo tên hoặc đường dẫn...", text: $vm.diskSearchText)
                    .textFieldStyle(.plain)
                if !vm.diskSearchText.isEmpty {
                    Button {
                        vm.diskSearchText = ""
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

            Spacer()

            Button {
                Task { await vm.scanDisk() }
            } label: {
                if vm.isDiskScanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang phân tích...")
                    }
                } else {
                    Label("Quét lại", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isDiskScanning || vm.isRemoving)

            Button(role: .destructive) {
                showTrashConfirm = true
            } label: {
                Label("Chuyển vào Thùng rác (\(vm.diskSelectedFiles.count))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.diskSelectedFiles.isEmpty || vm.isRemoving || vm.isDiskScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Thư mục chiếm nhiều dung lượng")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Hiện mục ẩn", isOn: $vm.diskShowHiddenFolders)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Text(ByteFormat.string(from: vm.diskFoldersTotalBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if vm.isDiskScanning && vm.diskFolders.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Đang đo dung lượng thư mục...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.visibleDiskFolders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("Không có thư mục nào để hiển thị.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSize = max(vm.visibleDiskFolders.map(\.sizeBytes).max() ?? 1, 1)
                List(vm.visibleDiskFolders) { folder in
                    Button {
                        Task { await vm.setDiskRoot(folder.url) }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue.opacity(0.85))
                                .font(.system(size: 15))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.16))
                                        Capsule()
                                            .fill(folder.sizeBytes >= 5 * 1024 * 1024 * 1024 ? Color.orange : Color.blue.opacity(0.8))
                                            .frame(width: geo.size.width * max(0.03, min(1.0, Double(folder.sizeBytes) / Double(maxSize))))
                                    }
                                }
                                .frame(height: 4)
                            }

                            Spacer()

                            Text(ByteFormat.string(from: folder.sizeBytes))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Mở thư mục này")
                }
                .listStyle(.inset)
            }

            Divider()
            Text("Bấm vào thư mục để xem bên trong. Chỉ số dung lượng là dung lượng thực tế trên đĩa.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
    }

    private var filePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Tệp lớn nhất")
                    .font(.subheadline.weight(.semibold))
                Text("\(vm.filteredLargeFiles.count)/\(vm.diskLargeFiles.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Chọn tất cả") {
                    vm.selectAllFilteredDiskFiles()
                }
                .controlSize(.small)
                .disabled(vm.filteredLargeFiles.isEmpty)

                Button("Bỏ chọn") {
                    vm.clearDiskSelection()
                }
                .controlSize(.small)
                .disabled(vm.diskSelectedFiles.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if vm.isDiskScanning && vm.diskLargeFiles.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Đang tìm các tệp lớn hơn \(ByteFormat.string(from: vm.diskMinSize))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Quét toàn bộ Home có thể mất vài chục giây ở lần đầu.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredLargeFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(vm.diskSearchText.isEmpty
                        ? "Không có tệp nào vượt ngưỡng \(ByteFormat.string(from: vm.diskMinSize))."
                        : "Không có tệp nào khớp bộ lọc.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    if vm.diskSearchText.isEmpty {
                        Text("Thử hạ ngưỡng kích thước hoặc chọn phạm vi khác.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSize = max(vm.filteredLargeFiles.map(\.sizeBytes).max() ?? 1, 1)
                List(vm.filteredLargeFiles) { file in
                    LargeFileRow(
                        file: file,
                        icon: vm.icon(forPath: file.url.path),
                        maxSizeBytes: maxSize,
                        dateLabel: file.modified.map { Self.dateFormatter.string(from: $0) } ?? "—",
                        onToggle: { vm.toggleDiskSelection(file) }
                    )
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("Chỉ tính tệp đơn lẻ, không đi vào bên trong gói .app / .photoslibrary.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if !vm.diskSelectedFiles.isEmpty {
                    Text("Đã chọn \(ByteFormat.string(from: vm.diskSelectedBytes))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = vm.diskRootURL
        panel.prompt = "Phân tích thư mục này"
        panel.message = "Chọn thư mục bạn muốn phân tích dung lượng"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.setDiskRoot(url) }
        }
    }
}

private struct LargeFileRow: View {
    let file: LargeFileItem
    let icon: NSImage
    let maxSizeBytes: Int64
    let dateLabel: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: file.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundColor(file.isSelected ? .accentColor : .secondary)

                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(file.url.deletingLastPathComponent().path)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(dateLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 78, alignment: .trailing)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteFormat.string(from: file.sizeBytes))
                            .font(.callout.weight(.semibold))
                        let ratio = max(0.05, min(1.0, Double(file.sizeBytes) / Double(maxSizeBytes)))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule()
                                    .fill(file.sizeBytes >= 1024 * 1024 * 1024 ? Color.orange : Color.accentColor)
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        .frame(width: 76, height: 4)
                    }
                    .frame(width: 96, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AppRemover.revealInFinder(file.url)
            } label: {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Hiển thị trong Finder")
        }
        .padding(.vertical, 3)
    }
}

private struct DiskStatCard: View {
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
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
    }
}
