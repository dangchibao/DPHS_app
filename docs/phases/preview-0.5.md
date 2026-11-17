# Bản thử 0.5.0+5 — schema 21

Mốc tích hợp tiếp theo của phần mềm, chưa phải bản nghiệm thu dùng dữ liệu thật. Không triển khai cloud hoặc push GitHub.

## Phần bổ sung so với preview 0.4.0/schema 18

- Bảng size cấu hình theo sản phẩm/cửa hàng; gợi ý theo khoảng chiều cao/cân nặng, không hard-code quy đổi.
- CK xuất → giao vận chuyển → kiểm đếm nhận tại chi nhánh/máy chỉ định; giữ snapshot giá vốn, ghi chênh lệch, replay không nhân đôi tồn.
- Chấm công 0 / 0,5 / 1 ngày có lý do, sự kiện bất biến, trạng thái chờ/xác nhận/từ chối từ server, feed giới hạn quyền.
- Che bí mật/số lương trong audit, đóng trang riêng tư và hết phiên khi quyền thay đổi; xóa lease của phiên tương tác bị thu hồi, giữ nguyên outbox.
- Thanh đồng bộ hiện cả trên trang con; đóng kết nối database trước đổi cấu hình thiết bị; sửa mốc ngày mã chứng từ/MR/chấm công khi qua nửa đêm.

Lõi lương theo công/hoa hồng/bậc thưởng có kiểm thử dùng chung Dart/TypeScript, nhưng chưa có cấu hình lương lưu/đồng bộ riêng tư, chốt bảng lương hoặc phiếu lương. Không coi calculator là chức năng lương đã hoàn thành.

## Kiểm chứng

157 test Flutter và 125 test API đạt. Flutter analyze, API lint/typecheck/Worker dry-run, D1 local schema 21 đạt. Smoke HTTP workerd/database riêng đạt đăng nhập, tạo chi nhánh/đăng ký/duyệt máy, CK hai cửa hàng/nhận thiếu/replay, chấm công/feed riêng và chặn client cũ. Chưa nghiệm thu trên điện thoại thật hoặc cloud production; chưa có số đo CPU/billing production.

Windows release, Android APK và Web release biên dịch đạt, gồm Wasm dry-run của Web. EXE ProductVersion 0.5.0+5; APK versionCode 5/versionName 0.5.0, chữ ký v2 và quyền Internet đã xác minh. APK gồm arm64-v8a/armeabi-v7a/x86_64, vẫn ký debug. Web vẫn là khung giao diện, chưa có quản lý/báo cáo online hoàn chỉnh và không có POS offline.

Đã tạo ngoc-thanh-windows-0.5.0-preview.zip (19.560.572 byte) và ngoc-thanh-android-0.5.0-preview.apk (77.462.029 byte), có .sha256 bên cạnh. Kiểm tra toàn bộ 45 file ZIP khớp manifest hash/length, EXE khớp bản build và migration 21 trong ZIP/APK khớp source; checksum cả hai gói đạt. Các preview cũ giữ nguyên.

## Chạy thử

Tại repository: ./scripts/dev.ps1. Đăng nhập đúng vai trò rồi dùng menu Bảng size / Chuyển kho cửa hàng / Chấm công nhân viên. Chuyển kho cần hai danh tính máy đã đăng ký/duyệt và kết nối cloud local để gửi offer đến đích; không sao chép database tạo máy bán thứ hai.

Portable Windows phải giải nén toàn bộ ZIP, giữ EXE cùng DLL/data. APK preview ký debug, chưa phải khóa ký phát hành cuối. Tất cả gói chỉ dành dữ liệu thử. Không cài/khôi phục đè dữ liệu cửa hàng thật để nghiệm thu.

API tại mốc này yêu cầu schema tối thiểu 21 cho directory/sync. Cần dùng app và API tương thích; bản 0.4.0/schema 18 sẽ được yêu cầu cập nhật. Nâng schema tự sao lưu theo cấu hình, reset cursor để replay idempotent; chứng từ/kho/công nợ/counter/outbox được giữ và kiểm thử migration. Mật khẩu bootstrap đọc từ môi trường; không có mật khẩu cửa hậu trong gói.

## Còn lại

Bảng lương/phiếu lương, dashboard/báo cáo và Web quản lý online; bàn giao nhân viên/máy mất/quyền tồn; ảnh/QR cấu hình; backup cloud và nghiệm thu cuối. Chi tiết và giới hạn từng module nằm trong progress.md. Không bổ sung tính năng ngoài yêu cầu.
