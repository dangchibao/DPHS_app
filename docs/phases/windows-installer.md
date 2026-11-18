# Bổ sung bộ cài Windows — 17/11/2026

LEVEL 3: đóng gói có thao tác ghi/gỡ tệp và nâng cấp nên cần kiểm tra bảo vệ dữ liệu. Không đổi logic nghiệp vụ, app vẫn 0.7.0+7/schema 30.

## Đã làm

- Bộ cài EXE NSIS 3.13 tiếng Việt, per-user Windows 10/11 x64, đường dẫn cố định, shortcut menu Start và mục gỡ trong Apps. Không yêu cầu admin, không tự mở ứng dụng/gọi cloud.
- Chặn thư mục root/payload reparse, ghi đè đường dẫn bằng /D, phiên cài/gỡ song song, EXE bị khóa và hạ phiên bản đã đăng ký. Không tự tắt tiến trình bán hàng.
- Uninstaller chỉ xóa từng tệp đóng gói, shortcut và khóa riêng; không xóa đệ quy hoặc xóa SQLite/queue/backup. Installer không mở database và không thay danh tính máy.
- ZIP Windows bổ sung 10 DLL CRT x64 app-local từ Visual Studio redistributable, xác minh chữ ký Microsoft/kiến trúc, manifest runtime và tài liệu. ZIP hiện có 66 tệp manifest thay cho 54; EXE ứng dụng và schema giữ nguyên.
- Script build kiểm checksum ZIP, toàn bộ manifest, runtime và phiên bản NSIS; compiler warning làm build thất bại. Bộ cài có SHA-256 riêng. Thư mục Android build được Git bỏ qua.

## Kiểm chứng

- test-windows-installer.ps1 đạt trọn lượt thực tế trong artifacts/installer-tests/a41a1652d98c455393ab7281d6a34ec4: cài mới, so mọi hash payload/registry/shortcut, sửa chữa; junction và /D bị chặn; cài/gỡ lúc EXE khóa bị chặn; nâng fixture 0.7.0→0.7.1, hạ về 0.7.0 bị chặn; gỡ bỏ tệp chương trình/shortcut/registry, giữ tệp người dùng và checksum SQLite/outbox/backup mô phỏng. Không chạy EXE ứng dụng, không mở database thật. Nhãn 0.7.1 chỉ dùng trong fixture.
- Một lượt đầu phát hiện helper WScript COM của host không mở được tên lối tắt tiếng Việt qua ACP. Đã kiểm tra lại bằng bản sao cùng bytes mang tên ASCII; đọc đúng target EXE. Script test đã sửa và lượt trọn vẹn ở trên đã đạt.
- dumpbin kiểm EXE và mọi DLL native: các CRT import msvcp140.dll, vcruntime140_1.dll, vcruntime140.dll đều có trong ZIP.
- verify-release.ps1 -RequireRuntime: 66 file Windows manifest/hash/EXE/schema 30 khớp; APK schema 30/ba ABI/checksum khớp. PowerShell parser kiểm tất cả script, không lỗi.
- Không chạy lại Flutter/API/Python vì chỉ đổi đóng gói/tài liệu; kết quả nghiệp vụ giữ mốc trước: 204/169/19 test đã đạt, Flutter analyze sạch, ba nền tảng build đạt. Không ghi thành lượt test mới.

## Cách chạy thử và giới hạn

Xem ../operations/windows-installer.md. Bộ cài chưa ký Authenticode; APK vẫn ký debug. Chưa kiểm chứng máy Windows sạch hoặc mất điện giữa lúc installer ghi tệp; installer chưa có rollback nguyên gói. Bộ cài không thay thế backup trước nâng cấp. Chặn downgrade không áp dụng với việc người dùng tự mở EXE portable cũ. Chưa nghiệm thu cloud/GitHub/thiết bị thực và không tự deploy/push/phát sinh phí.

Đề xuất: không thêm tính năng ngoài yêu cầu.
