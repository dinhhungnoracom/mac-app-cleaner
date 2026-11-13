import SwiftUI

struct TrashView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var showDeleteSelectedConfirm = false
    @State private var showEmptyAllConfirm = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale(identifier: "vi_VN")
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            trashStatsStrip
            Divider()
            trashToolbar
            Divider()
            trashListContent
        }
        .alert("Xoá vĩnh viễn \(vm.selectedTrashItems.count) mục đã chọn?", isPresented: $showDeleteSelectedConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Xoá vĩnh viễn", role: .destructive) {
                Task { await vm.deleteSelectedTrashItems() }
            }
        } message: {
            Text(
                "Các mục này (\(ByteFormat.string(from: vm.selectedTrashBytes))) sẽ bị xoá vĩnh viễn khỏi máy Mac và không thể khôi phục."
            )
        }
        .alert("Dọn sạch toàn bộ Thùng rác?", isPresented: $showEmptyAllConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Dọn sạch Thùng rác", role: .destructive) {
                Task { await vm.emptyEntireTrash() }
            }
        } message: {
            let sizeText = vm.trashTotalBytes > 0
                ? " (\(ByteFormat.string(from: vm.trashTotalBytes)))"
                : ""
            Text("Toàn bộ các mục trong Thùng rác\(sizeText) sẽ bị xoá vĩnh viễn và không thể hoàn tác.")
        }
    }

    private var trashStatsStrip: some View {
        HStack(spacing: 12) {
            TrashStatCard(
                title: "Số mục trong Thùng rác",
                value: vm.trashPermissionDenied ? "Cần quyền" : "\(vm.trashItems.count)",
                subtitle: TrashService.trashURL.path,
                accent: .primary
            )
            TrashStatCard(
                title: "Dung lượng đang chiếm",
                value: vm.trashPermissionDenied ? "—" : ByteFormat.string(from: vm.trashTotalBytes),
                subtitle: "Có thể giải phóng ngay",
                accent: .orange
            )
            TrashStatCard(
                title: "Đã chọn để xoá",
                value: "\(vm.selectedTrashItems.count)",
                subtitle: ByteFormat.string(from: vm.selectedTrashBytes),
                accent: .red
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var trashToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm file / app trong Thùng rác...", text: $vm.trashSearchText)
                    .textFieldStyle(.plain)
                if !vm.trashSearchText.isEmpty {
                    Button {
                        vm.trashSearchText = ""
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

            Picker("Sắp xếp", selection: $vm.trashSort) {
                ForEach(TrashSort.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            if !vm.trashItems.isEmpty {
                Button("Chọn hết") {
                    vm.selectAllFilteredTrash()
                }
                .controlSize(.small)

                if !vm.selectedTrashItems.isEmpty {
                    Button("Bỏ chọn") {
                        vm.clearTrashSelection()
                    }
                    .controlSize(.small)
                }
            }

            Spacer()

            Button {
                TrashService.openTrashInFinder()
            } label: {
                Label("Mở Thùng rác", systemImage: "folder")
            }
            .controlSize(.regular)

            if !vm.selectedTrashItems.isEmpty {
                Button(role: .destructive) {
                    showDeleteSelectedConfirm = true
                } label: {
                    Label("Xoá mục đã chọn", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isRemoving)
            }

            Button(role: .destructive) {
                showEmptyAllConfirm = true
            } label: {
                Label("Dọn sạch Thùng rác", systemImage: "trash.slash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled((vm.trashItems.isEmpty && !vm.trashPermissionDenied) || vm.isRemoving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var trashListContent: some View {
        if vm.isScanningTrash {
            VStack(spacing: 12) {
                ProgressView()
                Text("Đang kiểm tra Thùng rác...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.trashPermissionDenied {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text("macOS đang hạn chế đọc trực tiếp ~/.Trash")
                    .font(.headline)
                Text("Bạn có thể cấp quyền Full Disk Access cho MacAppCleaner trong Cài đặt hệ thống, hoặc nhấn nút bên dưới để mở / dọn sạch Thùng rác trực tiếp qua Finder.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                HStack(spacing: 12) {
                    Button("Mở Thùng rác trong Finder") {
                        TrashService.openTrashInFinder()
                    }
                    Button("Dọn sạch Thùng rác qua Finder") {
                        showEmptyAllConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if vm.filteredTrashItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary)
                Text(vm.trashItems.isEmpty ? "Thùng rác đang trống" : "Không có mục nào khớp tìm kiếm")
                    .font(.headline)
                Text(vm.trashItems.isEmpty
                    ? "Các ứng dụng hoặc file rác bạn gỡ bỏ sẽ xuất hiện ở đây trước khi xoá vĩnh viễn."
                    : "Thử thay đổi từ khoá tìm kiếm.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let maxSize = max(vm.filteredTrashItems.map(\.sizeBytes).max() ?? 1, 1)
            List(vm.filteredTrashItems) { item in
                HStack(spacing: 12) {
                    Button {
                        vm.toggleTrashSelection(item)
                    } label: {
                        Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundColor(item.isSelected ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Image(nsImage: vm.icon(forPath: item.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            Text(itemTypeLabel(item))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(999)
                        }

                        HStack(spacing: 8) {
                            if let date = item.dateAddedToTrash {
                                Text("Bỏ vào: \(Self.dateFormatter.string(from: date))")
                            }
                            Text("•")
                            Text(item.path)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        AppRemover.revealInFinder(item.url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Hiển thị trong Finder")

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteFormat.string(from: item.sizeBytes))
                            .font(.callout.weight(.semibold))
                        let ratio = max(0.04, min(1.0, Double(item.sizeBytes) / Double(maxSize)))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule()
                                    .fill(item.sizeBytes >= 200 * 1024 * 1024 ? Color.orange : Color.red.opacity(0.8))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        .frame(width: 82, height: 4)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    vm.toggleTrashSelection(item)
                }
            }
            .listStyle(.inset)
        }
    }

    private func itemTypeLabel(_ item: TrashItem) -> String {
        if item.url.pathExtension.lowercased() == "app" {
            return "Ứng dụng"
        }
        return item.isDirectory ? "Thư mục" : "Tệp"
    }
}

private struct TrashStatCard: View {
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
