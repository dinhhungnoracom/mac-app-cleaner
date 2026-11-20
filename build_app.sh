#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
APP_NAME="MacAppCleaner"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "1. Đang build Swift release binary..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Không tìm thấy binary tại: ${BIN_PATH}"
  exit 1
fi

echo "2. Đang đóng gói ${APP_NAME}.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>vi</string>
    <key>CFBundleDisplayName</key>
    <string>Mac App Cleaner</string>
    <key>CFBundleExecutable</key>
    <string>MacAppCleaner</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.dinhdoong.MacAppCleaner</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacAppCleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>6</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "3. Đang tạo AppIcon.icns..."
ICONSET_DIR="${PROJECT_DIR}/.build/AppIcon.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

swift -e '
import AppKit
let outDir = CommandLine.arguments[1]
let sourcePngPath = CommandLine.arguments[2]
let sourceImage = NSImage(contentsOfFile: sourcePngPath)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, px) in sizes {
    let size = NSSize(width: px, height: px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx

    let rect = NSRect(origin: .zero, size: size)
    let pad = CGFloat(px) * 0.097
    let bgRect = rect.insetBy(dx: pad, dy: pad)
    let cornerRadius = bgRect.width * 0.2237
    let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Subtle macOS icon drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(px) * 0.018)
    shadow.shadowBlurRadius = CGFloat(px) * 0.032

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Clip to macOS squircle and draw custom 3D artwork
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    if let sourceImage {
        sourceImage.draw(
            in: bgRect,
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
    } else {
        let grad = NSGradient(
            starting: NSColor(calibratedRed: 0.14, green: 0.45, blue: 0.98, alpha: 1.0),
            ending: NSColor(calibratedRed: 0.03, green: 0.72, blue: 0.85, alpha: 1.0)
        )!
        grad.draw(in: path, angle: -45)
    }
    NSGraphicsContext.restoreGraphicsState()

    // Crisp subtle inner edge highlight
    if px >= 32 {
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = max(1.0, CGFloat(px) * 0.008)
        path.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
    }
}
' "${ICONSET_DIR}" "${PROJECT_DIR}/Assets/AppIconSource.png"

if iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns" 2>/dev/null; then
  echo "Đã tạo AppIcon.icns."
else
  echo "Bỏ qua iconutil (không ảnh hưởng chạy app)."
fi
rm -rf "${ICONSET_DIR}"

echo "4. Đang ký ad-hoc bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "5. Đang cài đặt vào /Applications/${APP_NAME}.app..."
DEST_APP="/Applications/${APP_NAME}.app"
rm -rf "${DEST_APP}"
ditto "${APP_BUNDLE}" "${DEST_APP}"
codesign --force --deep --sign - "${DEST_APP}" >/dev/null 2>&1 || true

echo "6. Hoàn tất! Ứng dụng đã sẵn sàng trong Applications:"
echo "   ${DEST_APP}"
