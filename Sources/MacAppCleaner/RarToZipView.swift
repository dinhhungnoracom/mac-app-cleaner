import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RarToZipView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            statsStrip
            Divider()
            toolbar
            Divider()
            optionsBar
            Divider()
            content
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [9, 6]))
                    .background(Color.accentColor.opacity(0.07))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.accentColor)
                            Text("Thả file .rar để thêm vào danh sách")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .padding(22)
                    .allowsHitTesting(false)
            }
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            RarStatCard(
                title: "File RAR đã thêm",
                value: "\(vm.rarJobs.count)",
                subtitle: ByteFormat.string(from: vm.rarSourceBytes),
                accent: .primary
            )
            RarStatCard(
                title: "Đã chuyển sang ZIP",
                value: "\(vm.rarCompletedCount)",
                subtitle: "Tổng ZIP: \(ByteFormat.string(from: vm.rarOutputBytes))",
                accent: .green
            )
            RarStatCard(
                title: "Nơi lưu",
                value: vm.rarOutputLabel,
                subtitle: "Giữ nguyên cấu trúc thư mục bên trong",
                accent: .blue
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                chooseFiles()
            } label: {
                Label("Thêm file RAR…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isConvertingRAR)

            Button("Xoá tất cả") {
                vm.clearRarJobs()
            }
            .controlSize(.small)
            .disabled(vm.rarJobs.isEmpty || vm.isConvertingRAR)

            Spacer()

            Menu {
                Button("Cùng thư mục với file gốc") {
                    vm.rarOutputMode = .sameFolder
                }
                Button("Thư mục Downloads") {
                    vm.rarOutputMode = .downloads
                }
                Divider()
                Button("Chọn thư mục…") {
                    chooseOutputFolder()
                }
            } label: {
                Label(vm.rarOutputLabel, systemImage: "folder")
            }
            .frame(width: 210)

            if vm.isConvertingRAR {
                Button("Huỷ") {
                    vm.cancelRarConversion()
                }
                .tint(.red)
            }

            Button {
                Task { await vm.convertRarJobs() }
            } label: {
                if vm.isConvertingRAR {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang chuyển...")
                    }
                } else {
                    Label("Chuyển sang ZIP (\(vm.rarPendingJobs.count))", systemImage: "arrow.right.doc.on.doc")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(vm.rarPendingJobs.isEmpty || vm.isConvertingRAR || !RarConverter.isAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var optionsBar: some View {
        HStack(spacing: 14) {
            Toggle("Xoá file RAR gốc sau khi chuyển", isOn: $vm.rarDeleteOriginal)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Mở Finder khi xong", isOn: $vm.rarRevealInFinder)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("Mật khẩu RAR (nếu có)", text: $vm.rarPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }
            .disabled(vm.isConvertingRAR)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !RarConverter.isAvailable {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.orange)
                Text("Thiếu công cụ bsdtar")
                    .font(.headline)
                Text("Máy này không có /usr/bin/bsdtar nên chưa chuyển đổi được.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.rarJobs.isEmpty {
            emptyState
        } else {
            List(vm.rarJobs) { job in
                RarJobRow(job: job) {
                    vm.removeRarJob(job)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 46))
                .foregroundStyle(.blue, .cyan)
            Text("Chuyển RAR sang ZIP")
                .font(.title3.bold())
            Text("macOS không mở được file .rar. Kéo file vào đây — app sẽ giải nén rồi đóng gói lại thành .zip đọc được ngay, không cần cài thêm phần mềm.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
            Button {
                chooseFiles()
            } label: {
                Label("Chọn file RAR…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Hỗ trợ RAR4 / RAR5 • Giữ nguyên cấu trúc thư mục • Có ô nhập mật khẩu")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "rar") ?? .data]
        panel.message = "Chọn một hoặc nhiều file .rar cần chuyển sang .zip"
        panel.prompt = "Thêm"
        if panel.runModal() == .OK {
            vm.addRarFiles(panel.urls)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = vm.rarCustomOutputDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Chọn thư mục lưu"
        panel.message = "Các file .zip sẽ được tạo trong thư mục này"
        if panel.runModal() == .OK, let url = panel.url {
            vm.setRarOutputDirectory(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                guard let url else { return }
                Task { @MainActor in
                    vm.addRarFiles([url])
                }
            }
        }
        return accepted
    }
}

private struct RarJobRow: View {
    let job: RarJob
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if RarConverter.looksMultiVolume(name: job.name) {
                        Text("Có thể là RAR nhiều phần")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .cornerRadius(999)
                    }
                }

                Text(job.source.deletingLastPathComponent().path)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusView
            }

            Spacer()

            Text(ByteFormat.string(from: job.sizeBytes))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            if case .done(let output, _) = job.status {
                Button {
                    AppRemover.revealInFinder(output)
                } label: {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Hiện file ZIP trong Finder")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(job.status.isWorking)
            .help("Bỏ khỏi danh sách")
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusView: some View {
        switch job.status {
        case .queued:
            Text("Chờ chuyển")
                .font(.caption)
                .foregroundColor(.secondary)
        case .working(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 150)
                Text(progress > 0 ? "\(Int(progress * 100))%" : "Đang chuẩn bị...")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 105, alignment: .leading)
            }
        case .done(_, let bytes):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Đã tạo ZIP • \(ByteFormat.string(from: bytes))")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }
}

private struct RarStatCard: View {
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
                .minimumScaleFactor(0.8)
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
