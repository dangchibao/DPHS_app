# Bộ cài Windows cho bản chạy thử

Người dùng tải ngoc-thanh-windows-0.7.0-setup-preview.exe cùng checksum tại artifacts/releases. Bộ cài tiếng Việt, dành Windows 10/11 x64, chỉ cài cho tài khoản Windows hiện tại, không yêu cầu admin. Đường dẫn cố định: %LOCALAPPDATA%/Programs/NgocThanhPOSPreview. Lối tắt nằm trong menu Start → Đồng phục Ngọc Thanh — Chạy thử. Gỡ bằng Settings → Apps hoặc uninstall.exe trong thư mục cài.

Bộ cài hiện chưa ký Authenticode; Windows có thể cảnh báo nhà phát hành chưa xác định. Chưa có chứng thư của chủ ứng dụng. Không tắt bảo vệ Windows để bỏ qua cảnh báo. Chỉ sử dụng tệp nguồn tin cậy và đối chiếu SHA-256; checksum cùng nguồn không thay thế chữ ký nhà phát hành.

Đóng ứng dụng trước khi cài lại/nâng cấp/gỡ. Bộ cài chặn khi EXE đang khóa, chặn hạ phiên bản đã đăng ký và chặn thư mục cài/payload bị chuyển hướng bằng junction/symlink. Không tự đóng tiến trình đang bán hàng. Lỗi khóa tệp/quyền thư mục phải xử lý rồi chạy lại; không có cơ chế hoàn tác toàn bộ cài đặt khi mất điện. Bản ZIP portable vẫn có để khôi phục tệp chương trình, sau khi đã sao lưu dữ liệu.

SQLite, hàng đợi, danh tính máy và backup nằm trong thư mục hỗ trợ ứng dụng hiện có, không đổi khi dùng bộ cài. Installer không mở/khởi tạo SQLite. Ứng dụng giữ cơ chế sao lưu trước migration khi mở lần đầu sau nâng cấp. Gỡ chỉ xóa danh sách tệp đã đóng gói, shortcut và khóa đăng ký của sản phẩm; không xóa đệ quy thư mục, không xóa dữ liệu/backup hoặc tệp người dùng thêm. Tệp chương trình cũ không còn thuộc gói mới có thể được giữ lại để tránh xóa nhầm. Không xem gỡ cài là cách đặt lại danh tính máy.

Chặn hạ phiên bản áp dụng với phiên bản đã đăng ký bằng bộ cài. Nó không thể chặn người dùng mở một EXE portable cũ. Giữ nguyên kiểm tra schema tại ứng dụng/API; không dùng EXE cũ để mở database mới. Luôn sao lưu trước nâng cấp.

## Đóng gói từ source

Build Flutter Windows trước, sau đó PowerShell 7:

```powershell
./scripts/package-preview.ps1
$env:NSIS_COMPILER = 'D:/tools/nsis-3.13/makensis.exe'
./scripts/package-windows-installer.ps1
./scripts/verify-release.ps1 -Version 0.7.0 -Schema 30 -CompareBuiltExe -RequireRuntime -Installer
```

Compiler NSIS 3.13 chạy portable, không cài dịch vụ hoặc sử dụng cloud. Tải bản ZIP từ [trang chính thức NSIS](https://nsis.sourceforge.io/Download), xem [giấy phép NSIS](https://nsis.sourceforge.io/License). Đây là công cụ đóng gói, không thay đổi stack ứng dụng. ZIP 3.13 đã dùng trong phiên kiểm chứng có SHA-256 BA63DFFC4410EE89193E1CB5A41989991BD77C61068DA17E3156D136B7B0B3D8; đây là hash đo tại môi trường, không phải chứng thực độc lập của nhà phát hành. Công cụ nằm trong artifacts/tools được Git bỏ qua; không tự tải/chạy từ build script. Compiler khác phiên bản, cảnh báo compiler, thiếu runtime hoặc manifest sai đều dừng build.

ZIP nguồn đã có [CRT app-local](windows-runtime.md), manifest và checksum. Installer kiểm lại mọi file trong ZIP trước khi nhúng payload và tạo checksum riêng cho EXE. Không chứa mật khẩu quản trị hay token; không gọi cloud, không tự mở app sau cài.

## Kiểm thử cài/nâng cấp/gỡ

```powershell
./scripts/test-windows-installer.ps1 -NsisCompiler $env:NSIS_COMPILER
```

Script tạo GUID dưới artifacts/installer-tests và khóa HKCU/Software/NgocThanh/InstallerTests/GUID riêng; không đăng ký sản phẩm thật, không mở SQLite thật. Các phiên bản 0.7.0/0.7.1 trong fixture là nhãn thử cơ chế nâng cấp, không phải bản ứng dụng 0.7.1 đã phát hành. Kết quả được ghi ở docs/phases/windows-installer.md. Giữ fixture để kiểm tra; không tự xóa dữ liệu dự án. Nếu kiểm thử bị ngắt, chỉ chạy uninstall.exe của đúng GUID fixture để dọn đăng ký thử.

Lượt thử này không thay thế nghiệm thu trên máy Windows sạch, ký phát hành hoặc diễn tập mất điện lúc installer đang ghi file. Chưa kiểm chứng cài cho tài khoản Windows khác trên máy vật lý khác.
