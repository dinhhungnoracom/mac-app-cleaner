<div align="center">

<img src="docs/assets/app-icon.png" width="128" height="128" alt="Mac App Cleaner Logo" style="border-radius: 28px; box-shadow: 0 16px 32px rgba(0,0,0,0.3);" />

# Mac App Cleaner

**Ứng dụng macOS bản địa (Native Swift & SwiftUI) dọn dẹp ứng dụng & làm sạch Thùng rác.**  
*Fast, Safe, and 100% Open Source macOS App Uninstaller & Trash Cleaner.*

[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple&style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white&style=flat-square)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/badge/Release-v1.1.1-green.svg?style=flat-square)](releases/)
[![GitHub Pages](https://img.shields.io/badge/Website-GitHub%20Pages-blueviolet?style=flat-square)](https://dinhhungnoracom.github.io/mac-app-cleaner/)

[**🌐 Trang chủ & Tải về (Website)**](https://dinhhungnoracom.github.io/mac-app-cleaner/) • [**📦 Tải bản .DMG**](docs/downloads/MacAppCleaner-v1.1.1.dmg) • [**Báo lỗi (Issues)**](../../issues)

</div>

---

## 🆕 Có gì mới ở v1.1.1

- **Tab Giám sát nhanh hơn ~100×**: thay lệnh `ps` bằng `libproc`, hết tình trạng treo khi danh sách tiến trình dài (output `ps` vượt bộ đệm pipe 64 KB). Một lần cập nhật còn ~30 ms thay vì vài giây.
- **Tab Ổ đĩa không còn chặn UI**: dung lượng thư mục được đo song song và hiển thị dần (thư mục đầu tiên sau ~0,3 s, danh sách tệp sau ~1,3 s), kết quả được cache 10 phút nên mở lại gần như tức thì.
- **Quét dung lượng nhanh gấp đôi**: dùng `fts` (cùng cơ chế `du`) thay vì `FileManager.enumerator`.
- **Tab Dọn dẹp nhanh hơn** (~30%) nhờ dùng chung bộ đo dung lượng mới.
- Sửa lỗi nhãn Picker bị ép dọc ở tab Giám sát.

## 🆕 Có gì mới ở v1.1.0

- **Tab Dọn dẹp**: 8 nhóm rác được quét song song, có thanh dung lượng, chọn theo nhóm, xem chi tiết từng mục và chế độ xoá an toàn qua Thùng rác.
- **Tab Ổ đĩa**: đo dung lượng thư mục, chuyển sang thư mục con, tìm tệp lớn theo ngưỡng và xoá an toàn.
- **Rác mồ côi**: phát hiện tàn dư của ứng dụng đã gỡ, có bộ lọc nhà phát hành để giảm báo nhầm.
- **Tab bar mới** 5 mục, phím tắt `⌘1` … `⌘5`, header gọn hơn; nút "Chọn nhiều" chuyển vào thanh công cụ của tab Ứng dụng.
- Toàn bộ thao tác xoá đều đi qua lớp kiểm tra đường dẫn (`CleanupSafety` / `DiskAnalyzer.isSafeToTrash`), chặn `/System`, `~/Library/Keychains`, thư mục gốc và file đang dùng.

---

## 🌟 Tính năng nổi bật / Features

- ⚡ **Thuần bản địa & Siêu nhanh**: Viết 100% bằng **Swift & SwiftUI**, gọi trực tiếp API `AppKit`, `Bundle`, `CoreServices` và `NSWorkspace`. Không dùng Electron cồng kềnh, tiêu tốn rất ít RAM.
- 🧹 **Quét sâu file rác `~/Library`**: Tự động phát hiện chính xác các file liên quan của ứng dụng:
  - `Application Support`
  - `Caches`
  - `Preferences`
  - `Containers` & `Group Containers`
  - `Logs` & `Saved Application State`
  - `HTTPStorages`, `WebKit`, `LaunchAgents`
- 🧼 **Dọn dẹp thông minh (Smart Cleanup)**: Quét một lượt cache ứng dụng, logs, `DerivedData`/`DeviceSupport` của Xcode, bản sao lưu iPhone/iPad, cache trình duyệt và cache trong `Containers`. Xem từng mục, chọn lọc rồi dọn vào Thùng rác hoặc xoá vĩnh viễn.
- 💽 **Phân tích ổ đĩa (Disk Analyzer)**: Đo dung lượng thực tế của từng thư mục trong Home, drill-down không giới hạn, tìm nhanh các tệp lớn nhất (≥ 50 MB → 1 GB) và chuyển thẳng vào Thùng rác.
- 👻 **Phát hiện rác mồ côi**: Dò các thư mục `Application Support`, `Preferences`, `Containers`, `Group Containers`, `LaunchAgents`... có tên bundle ID nhưng không còn ứng dụng nào sở hữu — kèm cảnh báo "Cần kiểm tra" và mặc định không chọn.
- 📊 **Theo dõi hoạt động (Activity Monitor)**: Giám sát thời gian thực mức sử dụng CPU hệ thống, bộ nhớ RAM (đang dùng / trống / nén) và ổ đĩa. Hiển thị danh sách mọi tiến trình đang chạy theo % CPU, RAM và cho phép Thoát hoặc Buộc dừng (Force Quit) ngay lập tức.
- 🗑️ **Tab chuyên biệt dọn Thùng rác (Clean Trash)**: Xem chi tiết dung lượng chiếm dụng trong `~/.Trash`, cho phép xoá vĩnh viễn từng mục đã chọn hoặc dọn sạch toàn bộ Thùng rác chỉ với 1 cú click.
- 🛡️ **An toàn tuyệt đối**:
  - Mọi ứng dụng bị gỡ đều được chuyển vào **Thùng rác macOS** trước (có thể khôi phục bất cứ lúc nào).
  - Tự động khoá bảo vệ các ứng dụng cốt lõi của hệ thống (Safari, Terminal, System Apps).
- 🍏 **Nhận diện kiến trúc CPU**: Hiển thị rõ Apple Silicon (M1/M2/M3/M4), Universal hoặc Intel (x86_64).
- 🔓 **100% Mã nguồn mở & Riêng tư**: Giấy phép MIT tự do. Không gắn quảng cáo, không thu thập telemetry hay gửi bất kỳ dữ liệu nào ra ngoài.

---

## 🚀 Tải về & Cài đặt / Download & Install

### Cách 1: Tải file `.dmg` (Khuyên dùng)
1. Tải bản mới nhất tại [Trang tải về](docs/downloads/MacAppCleaner-v1.1.1.dmg) hoặc mục [Releases](../../releases).
2. Mở file `MacAppCleaner-v1.1.1.dmg`.
3. Kéo biểu tượng **MacAppCleaner** vào thư mục **Applications**.

### Cách 2: Tải file `.zip`
Tải bản [MacAppCleaner-v1.1.1.zip](docs/downloads/MacAppCleaner-v1.1.1.zip), giải nén và kéo `MacAppCleaner.app` vào thư mục `/Applications`.

---

## 🛡️ Hướng dẫn mở lần đầu (Khắc phục cảnh báo Gatekeeper của macOS)

Vì đây là dự án mã nguồn mở miễn phí (chưa mua chứng chỉ doanh nghiệp $99/năm của Apple), macOS Gatekeeper sẽ hiện thông báo bảo vệ ở lần mở đầu tiên:

### Cách A: Chuột phải để Mở (Đơn giản nhất)
1. Vào thư mục **Applications**.
2. Nhấp **chuột phải** (hoặc giữ phím `Control` + click) vào **MacAppCleaner** → chọn **Mở (Open)**.
3. Nhấn **Mở (Open)** trên hộp thoại xác nhận của macOS. *(Từ lần sau bạn chỉ cần click đúp bình thường)*.

### Cách B: Qua Cài đặt hệ thống (System Settings)
1. Mở **Cài đặt hệ thống (System Settings)** → **Quyền riêng tư & Bảo mật (Privacy & Security)**.
2. Cuộn xuống phần *Bảo mật (Security)* → bấm nút **Vẫn mở (Open Anyway)** cạnh MacAppCleaner.

### Cách C: Bằng Terminal
```bash
xattr -cr /Applications/MacAppCleaner.app
```

---

## 🛠️ Tự build từ mã nguồn / Build from Source

### Yêu cầu
- macOS 13.0 (Ventura) trở lên
- Xcode 15+ hoặc Command Line Tools (`xcode-select --install`)
- Swift 5.9+ / Swift 6.0

```bash
# 1. Clone repository
git clone https://github.com/dinhhungnoracom/mac-app-cleaner.git
cd mac-app-cleaner

# 2. Build ứng dụng
./build_app.sh

# 3. Đóng gói ra bản .DMG và .ZIP trong thư mục releases/
./package_release.sh

# 4. Mở ứng dụng vừa build
open MacAppCleaner.app
```

---

## 🌐 Cách kích hoạt GitHub Pages cho Website giới thiệu

Trang web giới thiệu & tải xuống đã được chuẩn bị sẵn 100% trong thư mục `docs/`. Để kích hoạt trang web trên GitHub:

1. Đẩy code lên GitHub:
   ```bash
   git remote add origin https://github.com/<your-username>/mac-app-cleaner.git
   git branch -M main
   git push -u origin main
   ```
2. Trên trang GitHub repo, vào **Settings** → **Pages** (cột bên trái).
3. Tại mục **Build and deployment**:
   - **Source**: Chọn `Deploy from a branch`
   - **Branch**: Chọn `main` và thư mục `/docs`
   - Nhấn **Save**.
4. Sau 1 phút, trang web giới thiệu & tải app của bạn sẽ tự động chạy tại:  
   `https://<your-username>.github.io/mac-app-cleaner/`

---

## 📄 Cấu trúc thư mục dự án

```text
mac-app-cleaner/
├── Assets/                        # Tài nguyên icon 3D độ phân giải cao
│   └── AppIconSource.png
├── Sources/MacAppCleaner/         # Mã nguồn Swift / SwiftUI
│   ├── MacAppCleanerApp.swift     # Điểm khởi chạy @main
│   ├── ContentView.swift          # Giao diện chính (Tabs, SplitView)
│   ├── CleanupView.swift           # Giao diện tab Dọn dẹp
│   ├── CleanupService.swift        # Quét rác, phát hiện rác mồ côi, lớp an toàn
│   ├── DiskAnalyzerView.swift      # Giao diện tab Ổ đĩa
│   ├── DiskAnalyzerService.swift   # Đo dung lượng thư mục & tìm tệp lớn
│   ├── TrashView.swift             # Giao diện dọn Thùng rác
│   ├── ActivityMonitorView.swift   # Giao diện giám sát CPU, RAM & tiến trình
│   ├── SystemMonitorService.swift  # Đọc Mach host CPU, VM RAM & tiến trình ps
│   ├── AppStoreViewModel.swift     # Quản lý trạng thái, quét & lọc
│   ├── AppScanner.swift            # Quét /Applications và ~/Library
│   ├── AppRemover.swift            # Xoá an toàn vào Trash
│   ├── TrashService.swift          # Quét và dọn ~/.Trash
│   └── Models.swift                # Data models
├── docs/                          # Website giới thiệu & tải về (GitHub Pages)
│   ├── index.html
│   ├── style.css
│   ├── script.js
│   ├── assets/                    # Favicon & icon
│   └── downloads/                 # File .dmg, .zip & checksums
├── releases/                      # Thư mục lưu bản release build
│   ├── MacAppCleaner-v1.1.1.dmg
│   ├── MacAppCleaner-v1.1.1.zip
│   └── checksums.sha256
├── .github/workflows/build.yml    # CI/CD tự động build & release
├── build_app.sh                   # Script build .app
├── package_release.sh             # Script đóng gói .dmg & .zip
├── Package.swift                  # Swift Package Manager
└── LICENSE                        # Giấy phép MIT
```

---

## 📜 Giấy phép / License

Dự án này được phát hành dưới giấy phép [MIT License](LICENSE). Bạn hoàn toàn có thể tự do sử dụng, chỉnh sửa và đóng góp!

---

## 📝 Lịch sử thay đổi

Xem [CHANGELOG.md](CHANGELOG.md) để biết chi tiết từng phiên bản.
