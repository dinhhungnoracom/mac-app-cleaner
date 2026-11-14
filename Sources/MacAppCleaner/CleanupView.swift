import SwiftUI

struct CleanupView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var showCleanConfirm = false
    @State private var permanently = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale(identifier: "vi_VN")
        return df
    }()

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
            content
            if vm.cleanupSelectedCount > 0 {
                Divider()
                footer
            }
        }
        .alert(
            permanently
                ? "Xoá vĩnh viễn \(vm.cleanupSelectedCount) mục?"
                : "Chuyển \(vm.cleanupSelectedCount) mục vào Thùng rác?",
            isPresented: $showCleanConfirm
        ) {
            Button("Huỷ", role: .cancel) {}
            Button(permanently ? "Xoá vĩnh viễn" : "Chuyển vào Thùng rác", role: .destructive) {
                let permanent = permanently
                Task { await vm.cleanSelectedJunk(permanently: permanent) }
            }
        } message: {
            Text(
                permanently
                    ? "\(ByteFormat.string(from: vm.cleanupSelectedBytes)) sẽ bị xoá khỏi máy Mac và không thể khôi phục. Các ứng dụng liên quan có thể cần tải lại dữ liệu ở lần mở tới."
                    : "\(ByteFormat.string(from: vm.cleanupSelectedBytes)) sẽ được chuyển vào Thùng rác macOS. Bạn có thể khôi phục nếu cần."
            )
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            CleanupStatCard(
                title: "Có thể giải phóng",
                value: ByteFormat.string(from: vm.cleanupTotalBytes),
                subtitle: "\(vm.cleanupItemCount) mục trong \(vm.cleanupGroups.count) nhóm",
                accent: .blue
            )
            CleanupStatCard(
                title: "Đang chọn dọn",
                value: ByteFormat.string(from: vm.cleanupSelectedBytes),
                subtitle: "\(vm.cleanupSelectedCount) mục đã đánh dấu",
                accent: .green
            )
            CleanupStatCard(
                title: "Trạng thái quét",
                value: vm.isCleanupScanning ? "Đang quét" : (vm.cleanupHasScanned ? "Hoàn tất" : "Chưa quét"),
                subtitle: lastScanLabel,
                accent: vm.isCleanupScanning ? .orange : .primary
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var lastScanLabel: String {
        guard let date = vm.cleanupLastScan else {
            return "Nhấn Quét thông minh để bắt đầu"
        }
        return "Lần cuối: \(Self.dateFormatter.string(from: date)) \(Self.timeFormatter.string(from: date))"
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.scanJunk() }
            } label: {
                if vm.isCleanupScanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang quét...")
                    }
                } else {
                    Label("Quét thông minh", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isCleanupScanning || vm.isRemoving)

            Button("Chọn nhóm an toàn") {
                vm.selectSafeJunk()
            }
            .controlSize(.small)
            .disabled(vm.cleanupGroups.isEmpty)

            Button("Bỏ chọn") {
                vm.clearJunkSelection()
            }
            .controlSize(.small)
            .disabled(vm.cleanupSelectedCount == 0)

            Button(vm.cleanupGroups.allSatisfy(\.isExpanded) && !vm.cleanupGroups.isEmpty ? "Thu gọn" : "Mở rộng") {
                let expand = !(vm.cleanupGroups.allSatisfy(\.isExpanded) && !vm.cleanupGroups.isEmpty)
                vm.setAllJunkExpanded(expand)
            }
            .controlSize(.small)
            .disabled(vm.cleanupGroups.isEmpty)

            Spacer()

            Text("Rác mồ côi & tải về cũ mặc định không chọn — hãy kiểm tra trước khi xoá.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isCleanupScanning && vm.cleanupGroups.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Đang quét Cache, Logs, Xcode, Containers và tàn dư ứng dụng...")
                    .foregroundColor(.secondary)
                Text("Lần quét đầu có thể mất 10–30 giây tuỳ dung lượng máy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.cleanupHasScanned {
            emptyState
        } else if vm.cleanupGroups.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.green)
                Text("Máy Mac của bạn đang khá sạch")
                    .font(.headline)
                Text("Không tìm thấy nhóm dữ liệu rác nào đáng kể. Bạn có thể quét lại bất cứ lúc nào.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.cleanupGroups) { group in
                        JunkGroupCard(
                            group: group,
                            isExpanded: Binding(
                                get: {
                                    vm.cleanupGroups.first(where: { $0.id == group.id })?.isExpanded ?? false
                                },
                                set: { newValue in
                                    guard let index = vm.cleanupGroups.firstIndex(where: { $0.id == group.id }) else { return }
                                    vm.cleanupGroups[index].isExpanded = newValue
                                }
                            ),
                            onToggleGroup: { vm.toggleJunkGroup(group.id) },
                            onToggleItem: { item in vm.toggleJunkItem(item) }
                        )
                    }
                }
                .padding(14)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.blue, .cyan)
            Text("Dọn dẹp thông minh")
                .font(.title3.bold())
            Text("Quét Cache, Logs, DerivedData của Xcode, bản sao lưu iPhone, cache trình duyệt và tàn dư của ứng dụng đã gỡ.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                Task { await vm.scanJunk() }
            } label: {
                Label("Bắt đầu quét", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isCleanupScanning)

            Text("Mọi mục mặc định được chuyển vào Thùng rác macOS, không xoá vĩnh viễn.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Đã chọn \(vm.cleanupSelectedCount) mục")
                    .font(.callout.weight(.semibold))
                Text(ByteFormat.string(from: vm.cleanupSelectedBytes))
                    .font(.title3.bold())
                    .foregroundColor(.green)
            }

            Spacer()

            Button(role: .destructive) {
                permanently = true
                showCleanConfirm = true
            } label: {
                Label("Xoá vĩnh viễn", systemImage: "trash.slash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(vm.isRemoving)

            Button(role: .destructive) {
                permanently = false
                showCleanConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if vm.isRemoving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text("Dọn vào Thùng rác")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(vm.isRemoving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct JunkGroupCard: View {
    let group: JunkGroup
    @Binding var isExpanded: Bool
    let onToggleGroup: () -> Void
    let onToggleItem: (JunkItem) -> Void

    private var tint: Color {
        switch group.category {
        case .caches: return .blue
        case .logs: return .gray
        case .xcode: return .purple
        case .deviceBackups: return .indigo
        case .browserCaches: return .cyan
        case .containerCaches: return .teal
        case .oldDownloads: return .orange
        case .orphaned: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider()
                if group.category.requiresReview {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(reviewNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                }
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        JunkItemRow(item: item, tint: tint) {
                            onToggleItem(item)
                        }
                        if item.id != group.items.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16))
        )
    }

    private var reviewNote: String {
        switch group.category {
        case .orphaned:
            return "Đây là các thư mục có tên giống bundle ID nhưng không khớp ứng dụng nào đang cài. Có thể là tàn dư app đã gỡ, cũng có thể thuộc về công cụ dòng lệnh hoặc app chạy nền — hãy kiểm tra đường dẫn trước khi xoá."
        case .oldDownloads:
            return "Chỉ gồm tệp không được mở/chỉnh sửa trong hơn 90 ngày. Đây là dữ liệu của bạn, không phải file hệ thống."
        default:
            return ""
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onToggleGroup) {
                Image(systemName: group.allSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundColor(group.allSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Chọn / bỏ chọn cả nhóm")

            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.category.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.14))
                        .cornerRadius(7)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.category.title)
                                .font(.body.weight(.semibold))
                            if group.category.requiresReview {
                                Text("Cần kiểm tra")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.16))
                                    .foregroundColor(.orange)
                                    .cornerRadius(999)
                            }
                        }
                        Text(group.category.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormat.string(from: group.totalBytes))
                            .font(.callout.weight(.semibold))
                        Text("\(group.items.count) mục • đã chọn \(group.selectedItems.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct JunkItemRow: View {
    let item: JunkItem
    let tint: Color
    let onToggle: () -> Void

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        df.locale = Locale(identifier: "vi_VN")
        return df
    }()

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundColor(item.isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(item.detail)
                            if let modified = item.modified {
                                Text("•")
                                Text(Self.dateFormatter.string(from: modified))
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }

                    Spacer()

                    Text(ByteFormat.string(from: item.sizeBytes))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(item.sizeBytes >= 1024 * 1024 * 1024 ? tint : .primary)
                        .frame(width: 84, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AppRemover.revealInFinder(item.url)
            } label: {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Hiển thị trong Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct CleanupStatCard: View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
    }
}
