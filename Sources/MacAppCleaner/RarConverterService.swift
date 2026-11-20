import Foundation

// MARK: - Models

enum RarJobStatus: Equatable {
    case queued
    case working(Double)
    case done(output: URL, bytes: Int64)
    case failed(String)

    var isFinished: Bool {
        switch self {
        case .done: return true
        default: return false
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

struct RarJob: Identifiable {
    let id: String
    let source: URL
    let name: String
    let sizeBytes: Int64
    var status: RarJobStatus = .queued

    var path: String { source.path }
}

enum ConversionOutputMode: String, CaseIterable, Identifiable {
    case sameFolder
    case downloads
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameFolder: return "Cùng thư mục với file gốc"
        case .downloads: return "Thư mục Downloads"
        case .custom: return "Thư mục tuỳ chọn"
        }
    }
}

struct RarEntry: Hashable {
    let name: String
    let sizeBytes: Int64
    let isDirectory: Bool
}

struct RarConvertOutcome {
    let outputURL: URL
    let entryCount: Int
    let outputBytes: Int64
}

enum RarConversionError: LocalizedError {
    case notRar
    case emptyArchive
    case multiVolume
    case passphraseRequired
    case wrongPassphrase
    case cancelled
    case toolUnavailable
    case noSpace(required: Int64, available: Int64)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRar:
            return "Tệp không phải định dạng RAR hợp lệ."
        case .emptyArchive:
            return "Archive RAR rỗng hoặc không có mục nào để chuyển."
        case .multiVolume:
            return "RAR nhiều phần (multi-volume) chưa được hỗ trợ. Hãy ghép đủ các phần thành một file .rar trước."
        case .passphraseRequired:
            return "File RAR có mật khẩu. Nhập mật khẩu ở ô bên dưới rồi thử lại."
        case .wrongPassphrase:
            return "Mật khẩu không đúng."
        case .cancelled:
            return "Đã huỷ chuyển đổi."
        case .toolUnavailable:
            return "Không tìm thấy /usr/bin/bsdtar trên máy."
        case .noSpace(let required, let available):
            return "Không đủ dung lượng trống: cần khoảng \(ByteFormat.string(from: required)), còn \(ByteFormat.string(from: available))."
        case .commandFailed(let message):
            return message
        }
    }
}

// MARK: - Cancellation handle

final class RarConversionTask {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate {
            process.terminate()
        }
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        running?.terminate()
    }
}

// MARK: - Converter

enum RarConverter {
    static let toolPath = "/usr/bin/bsdtar"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: toolPath)
    }

    static func isRarFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "rar" || ext == "rev" || isRarSignature(url)
    }

    /// RAR4: 52 61 72 21 1A 07 00 — RAR5: 52 61 72 21 1A 07 01 00
    static func isRarSignature(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8)
        guard data.count >= 7 else { return false }
        let header: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]
        guard Array(data.prefix(6)) == header else { return false }
        return data[6] == 0x00 || data[6] == 0x01
    }

    static func looksMultiVolume(_ url: URL) -> Bool {
        looksMultiVolume(name: url.lastPathComponent)
    }

    static func looksMultiVolume(name: String) -> Bool {
        let name = name.lowercased()
        if name.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) != nil {
            return true
        }
        return name.range(of: #"\.r\d{2}$"#, options: .regularExpression) != nil
    }

    static func availableDestination(for source: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base + ".zip")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(index)).zip")
            index += 1
        }
        return candidate
    }

    static func listEntries(
        of url: URL,
        password: String,
        task: RarConversionTask? = nil
    ) throws -> [RarEntry] {
        guard isRarSignature(url) else { throw RarConversionError.notRar }

        let result = try run(
            arguments: ["-tf", url.path],
            password: password,
            task: task,
            onLine: nil
        )
        guard !taskIsCancelled(task) else { throw RarConversionError.cancelled }
        guard result.status == 0 else {
            throw mapError(result.stderr, status: result.status)
        }

        let entries = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> RarEntry in
                let name = String(line)
                return RarEntry(name: name, sizeBytes: 0, isDirectory: name.hasSuffix("/"))
            }
        guard !entries.isEmpty else { throw RarConversionError.emptyArchive }
        return entries
    }

    static func convert(
        source: URL,
        destination: URL,
        password: String,
        task: RarConversionTask,
        onProgress: @escaping (Double) -> Void
    ) throws -> RarConvertOutcome {
        guard isAvailable else { throw RarConversionError.toolUnavailable }
        guard isRarSignature(source) else { throw RarConversionError.notRar }

        let entries = try listEntries(of: source, password: password, task: task)
        guard !task.isCancelled else { throw RarConversionError.cancelled }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("MacAppCleaner-RAR-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let total = max(entries.count, 1)
        var extracted = 0
        var lastReported = -1.0

        let extract = try run(
            arguments: ["-xvf", source.path, "-C", tempDir.path],
            password: password,
            task: task,
            onLine: { _ in
                extracted += 1
                let progress = min(0.9, Double(extracted) / Double(total) * 0.9)
                if progress - lastReported >= 0.01 {
                    lastReported = progress
                    onProgress(progress)
                }
            }
        )

        guard !task.isCancelled else { throw RarConversionError.cancelled }
        guard extract.status == 0 else {
            throw mapError(extract.stderr, status: extract.status)
        }

        let topLevel = (try? fm.contentsOfDirectory(atPath: tempDir.path)) ?? []
        guard !topLevel.isEmpty else { throw RarConversionError.emptyArchive }

        onProgress(0.93)

        let zipArguments = ["--format", "zip", "-cf", destination.path, "-C", tempDir.path, "--"] + topLevel
        let zip = try run(arguments: zipArguments, password: "", task: task, onLine: nil)

        guard !task.isCancelled else {
            try? fm.removeItem(at: destination)
            throw RarConversionError.cancelled
        }
        guard zip.status == 0 else {
            try? fm.removeItem(at: destination)
            throw mapError(zip.stderr, status: zip.status)
        }

        let attributes = try? fm.attributesOfItem(atPath: destination.path)
        let outputBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        onProgress(1.0)

        return RarConvertOutcome(
            outputURL: destination,
            entryCount: entries.count,
            outputBytes: outputBytes
        )
    }

    // MARK: Command runner

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func run(
        arguments: [String],
        password: String,
        task: RarConversionTask?,
        onLine: ((String) -> Void)?
    ) throws -> CommandResult {
        guard isAvailable else { throw RarConversionError.toolUnavailable }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)

        var args: [String] = []
        if !password.isEmpty {
            args += ["--passphrase", password]
        }
        args += arguments
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw RarConversionError.commandFailed(error.localizedDescription)
        }
        task?.attach(process)
        defer { task?.detach() }

        let ioQueue = DispatchQueue(label: "MacAppCleaner.RarConverter.io", attributes: .concurrent)
        let group = DispatchGroup()
        let stateLock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        group.enter()
        ioQueue.async {
            var collected = Data()
            var buffer = Data()
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                guard onLine != nil else { continue }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let text = String(data: lineData, encoding: .utf8), !text.isEmpty {
                        onLine?(text)
                    }
                }
            }
            if let onLine, !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8), !text.isEmpty {
                onLine(text)
            }
            stateLock.lock()
            stdoutData = collected
            stateLock.unlock()
            group.leave()
        }

        group.enter()
        ioQueue.async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            stateLock.lock()
            stderrData = data
            stateLock.unlock()
            group.leave()
        }

        // Đẩy từng dòng stdout ra callback được xử lý trong reader phía trên.

        process.waitUntilExit()
        group.wait()

        stateLock.lock()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        stateLock.unlock()

        if let task, task.isCancelled {
            throw RarConversionError.cancelled
        }

        return CommandResult(
            status: process.terminationStatus,
            stdout: stdout,
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func taskIsCancelled(_ task: RarConversionTask?) -> Bool {
        task?.isCancelled ?? false
    }

    private static func mapError(_ stderr: String, status: Int32) -> RarConversionError {
        let lowered = stderr.lowercased()
        if lowered.contains("passphrase") || lowered.contains("password") {
            if lowered.contains("incorrect") || lowered.contains("invalid") {
                return .wrongPassphrase
            }
            return .passphraseRequired
        }
        if lowered.contains("unrecognized archive") || lowered.contains("not a rar") {
            return .notRar
        }
        if lowered.contains("truncated") || lowered.contains("unexpected end") || lowered.contains("damaged") {
            return .multiVolume
        }
        if stderr.isEmpty {
            return .commandFailed("bsdtar thoát với mã \(status).")
        }
        return .commandFailed(stderr)
    }
}
