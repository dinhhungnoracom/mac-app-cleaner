# Changelog

Mọi thay đổi đáng chú ý của Mac App Cleaner được ghi ở đây.
Định dạng dựa trên [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/), phiên bản theo [Semantic Versioning](https://semver.org/lang/vi/).

## [1.3.0] — 2026-11-20

### Thêm mới

- **Tab "BAT → SH"**: dịch file batch Windows (.bat/.cmd) sang shell script chạy trên macOS.
  - Kéo–thả nhiều file; xem trước script và danh sách cảnh báo theo từng dòng trước khi lưu.
  - Dịch các lệnh phổ biến: `echo` (kể cả chuyển hướng `>` / `>>`), `set`, `set /a`, `set /p`,
    `if exist/defined/errorlevel`, `if ... ==`, `for ... in`, `cd`, `md`, `rd`, `del`,
    `copy`, `xcopy`, `move`, `ren`, `type`, `cls`, `pause`, `timeout`, `exit /b`,
    `call`, `where`, `findstr`, `start`.
  - Dịch biến `%VAR%`, tham số `%1..%9`, `%*`, `%~dp0`; biến vòng lặp `%%f` và
    modifier `%%~nf`, `%%~xf`, `%%~pf`.
  - Giữ cấu trúc khối `if/else/for`; khối không hỗ trợ bị comment kèm TODO thay vì chạy sai.
  - Cảnh báo rõ khi gặp đường dẫn ổ Windows (`C:\...`), `goto`, `for /f`, hoặc lệnh lạ.
  - Lưu `.sh` cùng thư mục gốc / Downloads / thư mục tuỳ chọn, tuỳ chọn `chmod +x`;
    **không bao giờ tự chạy** script.
- Dùng chung enum `ConversionOutputMode` cho cả hai công cụ chuyển đổi.

### Thay đổi

- Header chứa 7 tab: thu gọn nhãn tab, nút Cập nhật chỉ còn icon, chiều rộng cửa sổ
  tối thiểu 1120 px.
- Trạng thái đang tải của nút Cập nhật chỉ còn spinner (không còn chữ gây tràn header).

## [1.2.0] — 2026-11-18

### Thêm mới

- **Tab "RAR → ZIP"**: chuyển file `.rar` (macOS không mở được) thành `.zip` đọc được ngay.
  - Kéo–thả nhiều file hoặc chọn từ hộp thoại; hàng đợi hiển thị tiến độ từng file.
  - Nơi lưu: cùng thư mục gốc, Downloads, hoặc thư mục tuỳ chọn.
  - Dùng `libarchive` có sẵn trên macOS (`/usr/bin/bsdtar`) — không cần cài thêm phần mềm.
  - Hỗ trợ RAR4 và RAR5; giữ nguyên cấu trúc thư mục, thư mục rỗng và symlink.
  - Ô mật khẩu cho RAR mã hoá; cảnh báo khi file là RAR nhiều phần (multi-volume).
  - Huỷ giữa chừng, tuỳ chọn xoá file RAR gốc (vào Thùng rác) và mở Finder khi xong.
  - Không ghi đè: file trùng tên được đặt thành `ten (2).zip`, `ten (3).zip`...
  - Kiểm tra chữ ký RAR trước khi chạy, từ chối file giả mạo.

### Sửa lỗi

- `ByteFormat` hiển thị "0 KB" thay vì "Zero bytes" cho giá trị 0.
- Header gọn hơn (nút Cập nhật chỉ còn icon) để chứa 6 tab ở cửa sổ 1080 px.

## [1.1.1] — 2026-11-14

### Sửa lỗi

- **Tab Giám sát bị treo**: `ps` xuất 65.293 byte trong khi bộ đệm pipe chỉ 64 KB, khiến `waitUntilExit()` chờ vô hạn. Đã thay bằng `libproc` (`proc_listpids` + `proc_pidinfo`), không spawn tiến trình.
- %CPU giờ tính từ chênh lệch `pti_total_user/system` theo mach timebase (chuẩn hoá bằng `mach_timebase_info`).
- Nhãn Picker "Phạm vi" bị ép thành một cột chữ dọc ở tab Giám sát.
- `emptyEntireTrash` đọc hết stderr trước `waitUntilExit()` để tránh deadlock tương tự.
- Chặn chồng lấn khi timer 2 giây gọi `refreshMonitor()` liên tiếp.

### Hiệu năng

- Tab Giám sát: một lần cập nhật ~30 ms cho ~390 tiến trình (trước đây treo hoặc mất vài giây).
- Tab Ổ đĩa: đo dung lượng bằng `fts` song song — 18,5 s thay vì 36 s cho ~1 triệu tệp trong `~/Library`; thư mục đầu tiên hiện sau 0,3 s, danh sách tệp sau 1,3 s; UI không bị chặn trong lúc quét.
- Cache dung lượng thư mục 10 phút (`~/Library/Application Support/MacAppCleaner/folder-size-cache.json`): mở lại tab mất ~1,1 s.
- Tab Dọn dẹp nhanh hơn ~30% nhờ dùng chung bộ đo `fts`.
- Huỷ tác vụ đo cũ khi đổi phạm vi hoặc quét lại.

## [1.1.0] — 2026-11-14

### Thêm mới

- **Tab Dọn dẹp (Smart Cleanup)** với 8 nhóm rác:
  - Cache ứng dụng (`~/Library/Caches`)
  - Logs & báo cáo lỗi (`~/Library/Logs`)
  - Xcode: `DerivedData`, `iOS/watchOS/tvOS DeviceSupport`, `CoreSimulator/Caches`
  - Sao lưu iPhone/iPad (`MobileSync/Backup`)
  - Cache trình duyệt: Safari, Chrome, Edge, Firefox, Brave, Opera, Arc
  - Cache trong `Containers` (chỉ mục ≥ 5 MB)
  - Tệp tải về cũ hơn 90 ngày (mặc định không chọn)
  - **Rác mồ côi**: thư mục còn lại của app đã gỡ (mặc định không chọn)
- **Tab Ổ đĩa (Disk Analyzer)**:
  - Đo dung lượng thực tế của từng thư mục con, drill-down bằng cách bấm vào thư mục
  - Tìm tệp lớn theo ngưỡng 50 MB / 100 MB / 500 MB / 1 GB
  - Lọc theo tên/đường dẫn, chọn nhiều tệp và chuyển vào Thùng rác
  - Hiện/ẩn thư mục ẩn
- **Tab bar 5 mục** thay cho segmented control cũ; phím tắt `⌘1` … `⌘5`
- Nút "Chọn nhiều" được chuyển vào thanh công cụ của tab Ứng dụng

### An toàn

- Thêm lớp `CleanupSafety`: chỉ cho xoá đúng danh mục đã quét (cache, logs, Xcode, backup, Downloads...), chặn `/System`, `~/Library/Keychains`, thư mục gốc và `~/.Trash`
- `DiskAnalyzer.isSafeToTrash` chặn xoá ngoài Home, các thư mục gốc (Desktop/Documents/Downloads/Library/...) và Keychains
- Toàn bộ thao tác xoá mặc định đi qua Thùng rác macOS; chỉ xoá vĩnh viễn khi người dùng chọn rõ ràng
- Tệp trong Downloads được kiểm tra lại tuổi (≥ 90 ngày) ngay tại thời điểm xoá

### Hiệu năng

- Quét cleanup chạy song song theo nhóm: ~6 giây cho 205 mục / 12,5 GB trên máy thử nghiệm
- Tab Ổ đĩa hiển thị danh sách tệp lớn sau ~1 giây; dung lượng thư mục được tính tiếp ở nền
- Cache kích thước thư mục theo từng lần quét, không quét lại khi quay lại tab

### Sửa lỗi

- Loại bỏ việc tính trùng cache trình duyệt (trước đây `~/Library/Caches/Google` và cache Chrome bị cộng hai lần)
- Bỏ qua các mục 0 byte trong danh sách dọn dẹp
- Header không còn bị chật khi cửa sổ ở kích thước tối thiểu

## [1.0.0] — 2026-11-13

### Thêm mới

- Quét và gỡ ứng dụng trong `/Applications`, `~/Applications`, `/System/Applications`
- Phát hiện file rác trong `~/Library` (Application Support, Caches, Preferences, Containers, Group Containers, Logs, Saved State, HTTPStorages, WebKit, LaunchAgents)
- Chọn nhiều ứng dụng để gỡ hàng loạt
- Tab Thùng rác: xem dung lượng, xoá từng mục hoặc dọn sạch
- Tab Giám sát: CPU, RAM, ổ đĩa, danh sách tiến trình, thoát/force quit
- Nhận diện nguồn cài (App Store / Homebrew / Direct), kiến trúc CPU, lần sử dụng cuối
