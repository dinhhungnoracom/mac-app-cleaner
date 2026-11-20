import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BatToShView: View {
    @ObservedObject var vm: AppStoreViewModel

    @State private var isDropTargeted = false
    @State private var pendingRunJob: BatJob?
    @State private var showRunConfirm = false

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
        .alert("Chạy script trong Terminal?", isPresented: $showRunConfirm) {
            Button("Huỷ", role: .cancel) { pendingRunJob = nil }
            Button("Chạy", role: .destructive) {
                if let job = pendingRunJob {
                    vm.runBatScript(job)
                }
                pendingRunJob = nil
            }
        } message: {
            Text("Script sẽ chạy với quyền của bạn trên máy này. Chỉ chạy khi bạn đã đọc preview và hiểu nội dung.")
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
                            Text("Thả file .bat / .cmd để chuyển")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .padding(22)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Header

    private var statsStrip: some View {
        HStack(spacing: 12) {
            BatStatCard(
                title: "File .bat/.cmd",
                value: "\(vm.batJobs.count)",
                subtitle: "Đã chuyển: \(vm.batReadyCount)",
                accent: .primary
            )
            BatStatCard(
                title: "Đã lưu script",
                value: "\(vm.batSavedCount)",
                subtitle: vm.batOutputFormat == .command
                    ? "Định dạng .command — double-click để chạy"
                    : "Định dạng .sh — mở bằng Terminal",
                accent: .green
            )
            BatStatCard(
                title: "Cảnh báo cần xem",
                value: "\(vm.batIssueCount)",
                subtitle: "Dòng không chuyển được sẽ được comment + ghi rõ",
                accent: vm.batIssueCount > 0 ? .orange : .secondary
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
                Label("Thêm file .bat…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isSavingBAT)

            Button("Xoá tất cả") {
                vm.clearBatJobs()
            }
            .controlSize(.small)
            .disabled(vm.batJobs.isEmpty || vm.isSavingBAT)

            Spacer()

            Menu {
                Button("Cùng thư mục với file gốc") {
                    vm.batOutputMode = .sameFolder
                }
                Button("Thư mục Downloads") {
                    vm.batOutputMode = .downloads
                }
                Divider()
                Button("Chọn thư mục…") {
                    chooseOutputFolder()
                }
            } label: {
                Label(vm.batOutputLabel, systemImage: "folder")
            }
            .frame(width: 210)

            Button {
                Task { await vm.saveBatScripts() }
            } label: {
                if vm.isSavingBAT {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang lưu...")
                    }
                } else {
                    Label("Lưu .\(vm.batOutputFormat.fileExtension) (\(vm.batReadyCount))", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(vm.batReadyCount == 0 || vm.isSavingBAT)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var optionsBar: some View {
        HStack(spacing: 14) {
            Picker("Định dạng", selection: $vm.batOutputFormat) {
                ForEach(BatOutputFormat.allCases) { format in
                    Text(format.shortTitle).tag(format)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 195)

            Toggle("Cấp quyền chạy (chmod +x)", isOn: $vm.batMakeExecutable)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Mở Finder khi xong", isOn: $vm.batRevealInFinder)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            Text("macOS mở .sh bằng trình soạn thảo — chọn .command để double-click là chạy.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.batJobs.isEmpty {
            emptyState
        } else {
            HSplitView {
                jobList
                    .frame(minWidth: 330, idealWidth: 400)
                previewPane
                    .frame(minWidth: 480)
            }
        }
    }

    private var jobList: some View {
        List(vm.batJobs) { job in
            Button {
                vm.selectedBatJobID = job.id
            } label: {
                BatJobRow(job: job, isSelected: vm.selectedBatJobID == job.id)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                vm.selectedBatJobID == job.id
                    ? Color.accentColor.opacity(0.16)
                    : Color.clear
            )
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var previewPane: some View {
        if let job = vm.selectedBatJob {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundColor(.secondary)
                    Text(job.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let result = job.result, result.warningCount > 0 {
                        Text("\(result.warningCount) cảnh báo")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .cornerRadius(999)
                    }
                    Spacer()
                    if let result = job.result {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.script, forType: .string)
                        } label: {
                            Label("Sao chép", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                    if case .saved = job.status {
                        Button {
                            pendingRunJob = job
                            showRunConfirm = true
                        } label: {
                            Label("Chạy", systemImage: "play.fill")
                        }
                        .controlSize(.small)
                        .tint(.green)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider()

                if let result = job.result {
                    ScrollView {
                        Text(result.script)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))

                    Divider()
                    issuesPane(result.issues)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.red)
                        Text("Không đọc được file này")
                            .font(.headline)
                        Text(errorMessage(for: job))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text("Chọn một file .bat để xem bản chuyển")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func issuesPane(_ issues: [BatTranslationIssue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(issues.isEmpty ? "Không có cảnh báo" : "Cảnh báo (\(issues.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(issues.isEmpty ? .secondary : .orange)
                Spacer()
                Text("Dòng trong file .bat gốc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if issues.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Các lệnh trong file đều đã được dịch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(issues) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Text("Dòng \(issue.line)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundColor(.orange)
                                    .frame(width: 62, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Text(issue.source.trimmingCharacters(in: .whitespaces))
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)

                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(height: 170)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44))
                .foregroundStyle(.blue, .cyan)
            Text("Chuyển BAT sang SH")
                .font(.title3.bold())
            Text("Dịch file batch của Windows sang shell script chạy trên macOS. Các lệnh phổ biến (echo, set, if, for, copy, del, cd...) được chuyển tự động; chỗ không tương đương sẽ được đánh dấu TODO để bạn kiểm tra.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                chooseFiles()
            } label: {
                Label("Chọn file .bat…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Batch ≠ shell: luôn xem preview và kiểm thử trước khi chạy. File .sh mở bằng trình soạn thảo khi double-click; chọn .command nếu muốn chạy ngay.")
                .font(.caption)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorMessage(for job: BatJob) -> String {
        if case .failed(let message) = job.status {
            return message
        }
        return "Không có nội dung để hiển thị."
    }

    // MARK: - Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "bat") ?? .data, UTType(filenameExtension: "cmd") ?? .data]
        panel.message = "Chọn một hoặc nhiều file .bat / .cmd"
        panel.prompt = "Thêm"
        if panel.runModal() == .OK {
            vm.addBatFiles(panel.urls)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = vm.batCustomOutputDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Chọn thư mục lưu"
        panel.message = "Các file .sh sẽ được tạo trong thư mục này"
        if panel.runModal() == .OK, let url = panel.url {
            vm.setBatOutputDirectory(url)
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
                    vm.addBatFiles([url])
                }
            }
        }
        return accepted
    }
}

private struct BatJobRow: View {
    let job: BatJob
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 26, height: 26)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                statusLine
            }

            Spacer()

            if let result = job.result, result.warningCount > 0 {
                Text("\(result.warningCount)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.16))
                    .foregroundColor(.orange)
                    .cornerRadius(999)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch job.status {
        case .ready:
            Text("Sẵn sàng chuyển")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .saved(let url):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Đã lưu \(url.lastPathComponent)")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }
}

private struct BatStatCard: View {
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
