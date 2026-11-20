import Foundation

// MARK: - Models

struct BatTranslationIssue: Identifiable, Hashable {
    let id = UUID()
    let line: Int
    let message: String
    let source: String
}

struct BatConversionResult {
    let script: String
    let issues: [BatTranslationIssue]
    let totalLines: Int
    let convertedLines: Int
    let unsupportedBlocks: Int

    var warningCount: Int { issues.count }
}

enum BatOutputFormat: String, CaseIterable, Identifiable {
    case command
    case shell

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .command: return "command"
        case .shell: return "sh"
        }
    }

    var title: String {
        switch self {
        case .command: return ".command — double-click để chạy"
        case .shell: return ".sh — chạy trong Terminal"
        }
    }

    var shortTitle: String {
        switch self {
        case .command: return ".command (double-click)"
        case .shell: return ".sh (Terminal)"
        }
    }
}

enum BatJobStatus: Equatable {
    case ready
    case saved(URL)
    case failed(String)

    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }
}

struct BatJob: Identifiable {
    let id: String
    let source: URL
    let name: String
    let sizeBytes: Int64
    var result: BatConversionResult?
    var status: BatJobStatus

    var path: String { source.path }
}

enum BatConversionError: LocalizedError {
    case unreadable
    case empty
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Không đọc được file .bat (định dạng văn bản không hợp lệ)."
        case .empty:
            return "File .bat rỗng."
        case .writeFailed(let message):
            return message
        }
    }
}

// MARK: - Converter

/// Chuyển file batch (.bat/.cmd) của Windows sang shell script (.sh) chạy trên macOS.
/// Đây là bộ dịch best-effort: lệnh nào không có tương đương sẽ được comment lại
/// và ghi vào danh sách cảnh báo, không bao giờ tự chạy script.
enum BatToShConverter {
    private enum BlockKind {
        case ifBlock
        case forBlock
    }

    private struct State {
        var output: [String] = []
        var issues: [BatTranslationIssue] = []
        var blocks: [BlockKind] = []
        var indent = 0
        var unsupportedDepth = 0
        var convertedLines = 0
        var unsupportedBlocks = 0
        var usesScriptDir = false

        var prefix: String { String(repeating: "    ", count: max(0, indent)) }

        mutating func emit(_ text: String, line: Int, source: String) {
            output.append(prefix + text)
            convertedLines += 1
        }

        mutating func issue(_ message: String, line: Int, source: String) {
            issues.append(BatTranslationIssue(line: line, message: message, source: source))
        }
    }

    static func availableDestination(
        for source: URL,
        in directory: URL,
        fileExtension: String = "sh"
    ) -> URL {
        let fm = FileManager.default
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base).\(fileExtension)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(index)).\(fileExtension)")
            index += 1
        }
        return candidate
    }

    static func convert(contentsOf url: URL) throws -> BatConversionResult {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else { throw BatConversionError.unreadable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BatConversionError.empty
        }
        return convert(text: text, fileName: url.lastPathComponent)
    }

    static func convert(text: String, fileName: String = "script.bat") -> BatConversionResult {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var state = State()

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                state.output.append("")
                continue
            }

            // Vùng không chuyển được: comment đến khi đóng ngoặc.
            if state.unsupportedDepth > 0 {
                state.output.append(state.prefix + "# " + rawLine)
                state.unsupportedDepth += parenDelta(trimmed)
                if state.unsupportedDepth <= 0 {
                    state.unsupportedDepth = 0
                    if !state.blocks.isEmpty {
                        state.blocks.removeLast()
                        state.indent = max(0, state.indent - 1)
                    }
                }
                continue
            }

            // Đóng khối
            if trimmed == ")" || trimmed == ");" {
                if let block = state.blocks.popLast() {
                    state.indent = max(0, state.indent - 1)
                    state.output.append(state.prefix + (block == .forBlock ? "done" : "fi"))
                } else {
                    state.output.append(state.prefix + "# )")
                }
                continue
            }

            // Comment
            if trimmed.hasPrefix("::") {
                state.output.append(state.prefix + "#" + trimmed.dropFirst(2))
                continue
            }
            if let match = match(#"^@?rem(\s+(.*))?$"#, in: trimmed), match.count >= 2 {
                state.output.append(state.prefix + "#" + (match.count > 2 ? " " + match[2] : ""))
                continue
            }

            // Bỏ các lệnh chỉ có ý nghĩa trên Windows
            if matches(#"^@?(echo\s+(off|on)|setlocal|endlocal|title\s+.*|color\s+\w+|chcp\s+\d+|prompt\s+.*)$"#, in: trimmed) {
                if matches(#"^@?echo\s+on$"#, in: trimmed) {
                    state.output.append(state.prefix + "set -x")
                }
                continue
            }

            // echo
            if matches(#"^@?echo\.?$"#, in: trimmed) {
                state.emit("echo", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?echo\.(.*)$"#, in: trimmed), !match[1].isEmpty {
                let raw = match[1]
                if let redirect = splitRedirection(raw) {
                    let content = convertVariables(redirect.body, state: &state, line: lineNumber, source: rawLine)
                    let target = convertPath(redirect.target, state: &state, line: lineNumber, source: rawLine)
                    state.emit(
                        "echo \"\(escapeForDoubleQuotes(content))\" \(redirect.operator) \(quote(target))",
                        line: lineNumber,
                        source: rawLine
                    )
                } else {
                    let content = convertVariables(raw, state: &state, line: lineNumber, source: rawLine)
                    state.emit("echo \"\(escapeForDoubleQuotes(content))\"", line: lineNumber, source: rawLine)
                }
                continue
            }
            if let match = match(#"^@?echo\s+(.*)$"#, in: trimmed), match.count > 1 {
                let raw = match[1]
                if let redirect = splitRedirection(raw) {
                    let content = convertVariables(redirect.body, state: &state, line: lineNumber, source: rawLine)
                    let target = convertPath(redirect.target, state: &state, line: lineNumber, source: rawLine)
                    state.emit(
                        "echo \"\(escapeForDoubleQuotes(content))\" \(redirect.operator) \(quote(target))",
                        line: lineNumber,
                        source: rawLine
                    )
                } else {
                    let content = convertVariables(raw, state: &state, line: lineNumber, source: rawLine)
                    state.emit("echo \"\(escapeForDoubleQuotes(content))\"", line: lineNumber, source: rawLine)
                }
                continue
            }

            // if ...
            if let result = translateIf(trimmed, line: lineNumber, source: rawLine, state: &state) {
                state.output.append(state.prefix + result.text)
                if result.opensBlock {
                    state.blocks.append(.ifBlock)
                    state.indent += 1
                }
                state.convertedLines += 1
                continue
            }

            // for ...
            if let result = translateFor(trimmed, line: lineNumber, source: rawLine, state: &state) {
                if result.supported {
                    state.output.append(state.prefix + result.text)
                    state.blocks.append(.forBlock)
                    state.indent += 1
                    state.convertedLines += 1
                } else {
                    state.output.append(state.prefix + "# TODO: " + rawLine)
                    state.issue("Vòng lặp for kiểu Windows chưa được hỗ trợ — đã comment cả khối.", line: lineNumber, source: rawLine)
                    state.unsupportedDepth = 1
                    state.blocks.append(.forBlock)
                    state.indent += 1
                    state.unsupportedBlocks += 1
                }
                continue
            }

            // else
            if let match = match(#"^@?\)?\s*else\s*\(?$"#, in: trimmed) {
                _ = match
                state.indent = max(0, state.indent - 1)
                state.output.append(state.prefix + "else")
                state.indent += 1
                continue
            }

            // set
            if let match = match(#"^@?set\s+/a\s+([A-Za-z_]\w*)\s*=\s*(.+)$"#, in: trimmed) {
                let expression = convertArithmetic(match[2], state: &state)
                state.emit("\(match[1])=$(( \(expression) ))", line: lineNumber, source: rawLine)
                state.issue("Biểu thức số học của Windows có thể khác cú pháp — kiểm tra lại.", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?set\s+/p\s+([A-Za-z_]\w*)\s*=\s*(.*)$"#, in: trimmed) {
                let prompt = match[2].isEmpty ? match[1] : match[2]
                state.emit("read -r -p \"\(escapeForDoubleQuotes(prompt))\" \(match[1])", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?set\s+"?([A-Za-z_]\w*)=(.*?)"?$"#, in: trimmed) {
                let value = convertVariables(match[2], state: &state, line: lineNumber, source: rawLine)
                state.emit("export \(match[1])=\"\(escapeForDoubleQuotes(value))\"", line: lineNumber, source: rawLine)
                continue
            }

            // cd / path
            if let match = match(#"^@?(?:cd|chdir)\s+(?:/d\s+)?(.*)$"#, in: trimmed) {
                let converted = convertPath(match[1], state: &state, line: lineNumber, source: rawLine)
                state.emit("cd \"\(escapeForDoubleQuotes(converted))\"", line: lineNumber, source: rawLine)
                continue
            }

            // mkdir
            if let match = match(#"^@?(?:md|mkdir)\s+(.+)$"#, in: trimmed) {
                let args = convertPathList(match[1], state: &state, line: lineNumber, source: rawLine)
                state.emit("mkdir -p \(args)", line: lineNumber, source: rawLine)
                continue
            }

            // rmdir / rd
            if let match = match(#"^@?(?:rd|rmdir)\s+(/s\s+)?(/q\s+)?(.+)$"#, in: trimmed) {
                let recursive = match[1].isEmpty == false
                let args = convertPathList(match[3], state: &state, line: lineNumber, source: rawLine)
                state.emit("\(recursive ? "rm -rf" : "rmdir") \(args)", line: lineNumber, source: rawLine)
                continue
            }

            // del / erase
            if let match = match(#"^@?(?:del|erase)\s+(.+)$"#, in: trimmed) {
                let options = match[1].lowercased()
                let recursive = options.contains("/s")
                let paths = stripSwitches(match[1])
                let args = convertPathList(paths, state: &state, line: lineNumber, source: rawLine)
                state.emit("\(recursive ? "rm -rf" : "rm -f") \(args)", line: lineNumber, source: rawLine)
                continue
            }

            // copy
            if let match = match(#"^@?copy\s+(.+)$"#, in: trimmed) {
                let paths = stripSwitches(match[1])
                state.emit("cp \(convertPathList(paths, state: &state, line: lineNumber, source: rawLine))", line: lineNumber, source: rawLine)
                continue
            }

            // xcopy
            if let match = match(#"^@?xcopy\s+(.+)$"#, in: trimmed) {
                let paths = stripSwitches(match[1])
                state.emit("cp -R \(convertPathList(paths, state: &state, line: lineNumber, source: rawLine))", line: lineNumber, source: rawLine)
                state.issue("xcopy được dịch thành cp -R; kiểm tra lại các tuỳ chọn /e /h /exclude.", line: lineNumber, source: rawLine)
                continue
            }

            // move / ren
            if let match = match(#"^@?move\s+(.+)$"#, in: trimmed) {
                let paths = stripSwitches(match[1])
                state.emit("mv \(convertPathList(paths, state: &state, line: lineNumber, source: rawLine))", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?(?:ren|rename)\s+(.+)$"#, in: trimmed) {
                let paths = stripSwitches(match[1])
                state.emit("mv \(convertPathList(paths, state: &state, line: lineNumber, source: rawLine))", line: lineNumber, source: rawLine)
                continue
            }

            // type
            if let match = match(#"^@?type\s+(.+)$"#, in: trimmed) {
                let paths = convertPathList(match[1], state: &state, line: lineNumber, source: rawLine)
                state.emit("cat \(paths)", line: lineNumber, source: rawLine)
                continue
            }

            // cls / pause / timeout / exit
            if matches(#"^@?cls$"#, in: trimmed) {
                state.emit("clear", line: lineNumber, source: rawLine)
                continue
            }
            if matches(#"^@?pause$"#, in: trimmed) {
                state.emit("read -r -p \"Nhấn Enter để tiếp tục...\" _", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?timeout\s+/t\s+(\d+).*$"#, in: trimmed) {
                state.emit("sleep \(match[1])", line: lineNumber, source: rawLine)
                continue
            }
            if matches(#"^@?exit$"#, in: trimmed) {
                state.emit("exit 0", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?exit\s+/b\s*(\d+)?$"#, in: trimmed) {
                state.emit("exit \(match.count > 1 && !match[1].isEmpty ? match[1] : "0")", line: lineNumber, source: rawLine)
                continue
            }

            // call
            if let match = match(#"^@?call\s+(.+)$"#, in: trimmed) {
                let target = transformBatPath(match[1])
                state.emit("bash \(quote(target))", line: lineNumber, source: rawLine)
                state.issue("call được dịch thành 'bash <script>.sh' — đảm bảo file .sh tương ứng tồn tại.", line: lineNumber, source: rawLine)
                continue
            }

            // where / findstr
            if let match = match(#"^@?where\s+(.+)$"#, in: trimmed) {
                state.emit("which \(match[1])", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^@?findstr\s+(/i\s+)?(.*)$"#, in: trimmed) {
                let insensitive = match[1].isEmpty == false
                state.emit("grep \(insensitive ? "-i " : "")\(match[2])", line: lineNumber, source: rawLine)
                state.issue("findstr chỉ được dịch một phần — kiểm tra biểu thức và tham số.", line: lineNumber, source: rawLine)
                continue
            }

            // start
            if let match = match(#"^@?start\s+(.*)$"#, in: trimmed) {
                let value = match[1].replacingOccurrences(of: "\"\"", with: "").trimmingCharacters(in: .whitespaces)
                state.emit("open \(quote(convertPath(value, state: &state, line: lineNumber, source: rawLine)))", line: lineNumber, source: rawLine)
                state.issue("start được dịch thành 'open' — hành vi mở ứng dụng có thể khác.", line: lineNumber, source: rawLine)
                continue
            }

            // goto / label
            if let match = match(#"^@?goto\s+(\S+)$"#, in: trimmed) {
                _ = match
                state.output.append(state.prefix + "# TODO: goto không có tương đương trong shell — cần viết lại bằng hàm/vòng lặp.")
                state.issue("goto không được hỗ trợ; nhánh này cần chỉnh tay.", line: lineNumber, source: rawLine)
                continue
            }
            if let match = match(#"^:(\w+)$"#, in: trimmed) {
                state.output.append(state.prefix + "# Nhãn: \(match[1])")
                continue
            }

            // Dòng còn lại: giữ nguyên nhưng cảnh báo
            let converted = convertVariables(trimmed, state: &state, line: lineNumber, source: rawLine)
            state.output.append(state.prefix + converted)
            state.issue("Chưa chắc lệnh này chạy đúng trên macOS — kiểm tra lại.", line: lineNumber, source: rawLine)
            state.convertedLines += 1
        }

        // Đóng các khối còn mở
        while let block = state.blocks.popLast() {
            state.indent = max(0, state.indent - 1)
            state.output.append(state.prefix + (block == .forBlock ? "done" : "fi"))
        }

        let header = makeHeader(fileName: fileName, usesScriptDir: state.usesScriptDir)
        let body = state.output.joined(separator: "\n")
        let script = header + "\n" + body + "\n"

        return BatConversionResult(
            script: script,
            issues: state.issues,
            totalLines: lines.count,
            convertedLines: state.convertedLines,
            unsupportedBlocks: state.unsupportedBlocks
        )
    }

    // MARK: - Header

    private static func makeHeader(fileName: String, usesScriptDir: Bool) -> String {
        var lines = [
            "#!/bin/bash",
            "#",
            "# Được chuyển tự động từ \"\(fileName)\" bởi Mac App Cleaner.",
            "# CẢNH BÁO: batch và shell không tương đương 1:1. Hãy đọc các dòng TODO",
            "# và kiểm thử trước khi chạy. Script này không tự động thực thi.",
            "#"
        ]
        lines.append("shopt -s nullglob  # vòng lặp glob không có kết quả sẽ bỏ qua, giống batch")
        if usesScriptDir {
            lines.append("SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private static func translateIf(
        _ line: String,
        line lineNumber: Int,
        source: String,
        state: inout State
    ) -> (text: String, opensBlock: Bool)? {
        guard matches(#"^@?if\b"#, in: line) else { return nil }
        let opensBlock = line.hasSuffix("(")
        let body = stripTrailingParen(line)

        // if not exist
        if let match = match(#"^@?if\s+not\s+exist\s+(.+)$"#, in: body) {
            let path = convertPath(match[1], state: &state, line: lineNumber, source: source)
            return makeIf("! -e \(quote(path))", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        if let match = match(#"^@?if\s+exist\s+(.+)$"#, in: body) {
            let path = convertPath(match[1], state: &state, line: lineNumber, source: source)
            return makeIf("-e \(quote(path))", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        if let match = match(#"^@?if\s+errorlevel\s+(\d+)$"#, in: body) {
            return makeIf("$? -ge \(match[1])", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        // if /i "a"=="b"
        if let match = match(#"^@?if\s+/i\s+"?%([A-Za-z_]\w*)%"?\s*==\s*"?([^"]*)"?$"#, in: body) {
            state.issue("So sánh /i (không phân biệt hoa thường) được dịch thành so sánh thường.", line: lineNumber, source: source)
            return makeIf("\"$\(match[1])\" = \"\(match[2])\"", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        // if "%A%"=="B"
        if let match = match(#"^@?if\s+"?%([A-Za-z_]\w*)%"?\s*==\s*"?([^"]*)"?$"#, in: body) {
            return makeIf("\"$\(match[1])\" = \"\(match[2])\"", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        // if defined VAR
        if let match = match(#"^@?if\s+defined\s+([A-Za-z_]\w*)$"#, in: body) {
            return makeIf("-n \"${\(match[1])-}\"", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }
        // if not defined
        if let match = match(#"^@?if\s+not\s+defined\s+([A-Za-z_]\w*)$"#, in: body) {
            return makeIf("-z \"${\(match[1])-}\"", opensBlock: opensBlock, line: lineNumber, source: source, state: &state)
        }

        state.issue("Điều kiện if chưa được nhận dạng đầy đủ — kiểm tra lại.", line: lineNumber, source: source)
        return ("# TODO: if \(body) — viết lại điều kiện cho shell", false)
    }

    private static func makeIf(
        _ condition: String,
        opensBlock: Bool,
        line: Int,
        source: String,
        state: inout State
    ) -> (text: String, opensBlock: Bool) {
        guard opensBlock else {
            state.issue("Câu lệnh if một dòng chưa được hỗ trợ — hãy viết lại thành khối if ... fi.", line: line, source: source)
            return ("# TODO: if một dòng — cần viết lại thủ công", false)
        }
        return ("if [ \(condition) ]; then", true)
    }

    private static func translateFor(
        _ line: String,
        line lineNumber: Int,
        source: String,
        state: inout State
    ) -> (text: String, supported: Bool)? {
        guard matches(#"^@?for\b"#, in: line) else { return nil }

        if let match = match(#"^@?for\s+%%([A-Za-z])\s+in\s+\((.*?)\)\s+do\s*\(?$"#, in: stripTrailingParen(line)) {
            let variable = match[1]
            let items = convertVariables(match[2], state: &state, line: lineNumber, source: source)
            state.usesScriptDir = state.usesScriptDir || line.contains("%~dp0")
            return ("for \(variable) in \(items); do", true)
        }

        if matches(#"^@?for\s+/[a-z]\s"#, in: line) {
            return ("", false)
        }

        return ("", false)
    }

    // MARK: - Text helpers

    private static func convertVariables(
        _ text: String,
        state: inout State,
        line: Int,
        source: String
    ) -> String {
        var result = text
        if result.contains("%~dp0") {
            state.usesScriptDir = true
            result = result.replacingOccurrences(of: "%~dp0", with: "${SCRIPT_DIR}/", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(of: "%*", with: "\"$@\"")

        for index in 1...9 {
            result = result.replacingOccurrences(of: "%\(index)", with: "$\(index)")
        }

        // Biến đổi tên file của for: %%~nf, %%~xf, %%~pf, %%~f ...
        result = replaceMatches(#"%%~([a-zA-Z])([A-Za-z0-9_])"#, in: result) { match, text in
            let modifier = capture(match, 1, in: text).lowercased()
            let variable = capture(match, 2, in: text)
            switch modifier {
            case "f":
                return "${\(variable)}"
            case "n":
                return "${\(variable)%.*}"
            case "x":
                return ".${\(variable)##*.}"
            case "p":
                return "$(dirname \"${\(variable)}\")/"
            case "d":
                return "/"
            default:
                state.issue("Biến đổi %%~\(modifier) chưa được hỗ trợ — kiểm tra lại.", line: line, source: source)
                return "${\(variable)}"
            }
        }

        // %%f (biến vòng lặp trong file .bat) -> $f
        result = replaceMatches(#"%%([A-Za-z])"#, in: result) { match, text in
            "$" + capture(match, 1, in: text)
        }

        result = replaceMatches(#"%([A-Za-z_][A-Za-z0-9_]*)%"#, in: result) { match, text in
            let name = capture(match, 1, in: text)
            return "${\(name)}"
        }

        if result.contains("%%") {
            result = result.replacingOccurrences(of: "%%", with: "%")
        }

        for index in 1...9 {
            result = result.replacingOccurrences(of: "%%\(index)", with: "$$\(index)")
        }

        return result
    }

    private static func convertArithmetic(_ expression: String, state: inout State) -> String {
        var result = expression
        result = result.replacingOccurrences(of: "%%", with: "%")
        result = replaceMatches(#"%([A-Za-z_][A-Za-z0-9_]*)%"#, in: result) { match, text in
            capture(match, 1, in: text)
        }
        return result
    }

    private static func convertPath(
        _ raw: String,
        state: inout State,
        line: Int,
        source: String
    ) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        value = convertVariables(value, state: &state, line: line, source: source)

        if let match = match(#"^([A-Za-z]):[\\/](.*)$"#, in: value), match.count >= 3 {
            let drive = match[1].lowercased()
            let rest = match[2].replacingOccurrences(of: "\\", with: "/")
            state.issue("Đường dẫn ổ \(drive.uppercased()): không tồn tại trên macOS — sửa lại đường dẫn.", line: line, source: source)
            return "/\(drive)/\(rest)"
        }

        return value.replacingOccurrences(of: "\\", with: "/")
    }

    private static func convertPathList(
        _ raw: String,
        state: inout State,
        line: Int,
        source: String
    ) -> String {
        // Tách theo khoảng trắng nhưng giữ nguyên phần trong ngoặc kép.
        let parts = splitArguments(raw)
        let converted = parts.map { part -> String in
            if part.hasPrefix("-") || part.hasPrefix("/") && !part.contains("\\") && !part.contains("/") {
                return part
            }
            return quote(convertPath(part, state: &state, line: line, source: source))
        }
        return converted.joined(separator: " ")
    }

    private static func stripSwitches(_ raw: String) -> String {
        let parts = splitArguments(raw)
        return parts.filter { !$0.hasPrefix("/") }.joined(separator: " ")
    }

    private static func splitArguments(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func transformBatPath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasSuffix(".bat") || value.lowercased().hasSuffix(".cmd") {
            value = String(value.dropLast(4))
        }
        return value.replacingOccurrences(of: "\\", with: "/")
    }

    private static func escapeForDoubleQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private static func quote(_ text: String) -> String {
        "\"\(escapeForDoubleQuotes(text))\""
    }

    private static func splitRedirection(_ text: String) -> (body: String, `operator`: String, target: String)? {
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ">" && !inQuotes {
                let next = text.index(after: index)
                let isAppend = next < text.endIndex && text[next] == ">"
                let operatorText = isAppend ? ">>" : ">"
                let targetStart = isAppend ? text.index(after: next) : next
                let target = text[targetStart...].trimmingCharacters(in: .whitespaces)
                let body = text[..<index].trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty else { return nil }
                return (body, operatorText, target)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func stripTrailingParen(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        while value.hasSuffix("(") {
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    private static func parenDelta(_ line: String) -> Int {
        var delta = 0
        var inQuotes = false
        for character in line {
            if character == "\"" { inQuotes.toggle() }
            if inQuotes { continue }
            if character == "(" { delta += 1 }
            if character == ")" { delta -= 1 }
        }
        return delta
    }

    // MARK: - Regex

    private static func matches(_ pattern: String, in text: String) -> Bool {
        regex(pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let result = regex(pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<result.numberOfRanges).map { index in
            guard let range = Range(result.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }

    private static func replaceMatches(
        _ pattern: String,
        in text: String,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        let expression = regex(pattern)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(match, text))
        }
        return result
    }

    private static var cache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        if let cached = cache[pattern] { return cached }
        let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        cache[pattern] = expression
        return expression
    }
}
