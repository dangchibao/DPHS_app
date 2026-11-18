# Đồng phục Ngọc Thanh

Phần mềm POS và kho đồng phục học sinh Việt Nam, nhiều cửa hàng/thiết bị, Windows và Android offline-first. Web/PWA quản lý/báo cáo online. Tiền nguyên VND, UI tiếng Việt.

## Stack
Flutter 3.50 / Dart 3.14, Riverpod, Drift/SQLite; Cloudflare Workers TypeScript + D1; pdf/printing. Không Firebase. GitHub Actions kiểm tra cả app/API.

## Trạng thái
Phase 0 đã kiểm chứng. Đã có lõi local sản phẩm/kho/RBAC, đồng bộ theo lô, POS/PDF/tem, đặt cọc/thu công nợ nhiều lần, sao lưu/khôi phục và nhật ký. Source schema 30 hiện có [trường/lớp/học sinh](docs/phases/phase-5-schools.md) và [combo](docs/phases/phase-5-combos.md), [giá riêng/khuyến mãi/đại lý](docs/phases/phase-5-commercial.md), [may riêng](docs/phases/phase-6-tailoring.md), [đổi trả/hủy HD](docs/phases/phase-6-returns.md), [giữ hàng có hạn](docs/phases/phase-6-reservations.md), [đăng ký máy/quản trị chi nhánh](docs/phases/phase-7-device-enrollment.md), [bảng size/gợi ý](docs/phases/size-rules.md), [chuyển kho CK](docs/phases/transfers.md), [chấm công/bảo vệ phiên](docs/phases/attendance-session.md), [lương/phiếu lương](docs/phases/payroll.md), [báo cáo local](docs/phases/reports-local.md), [báo cáo cloud/Web online](docs/phases/reports-cloud-web.md), [pipeline backup cloud](docs/phases/cloud-backup.md). [Ảnh/QR/hạn mức cloud](docs/phases/media-bank-usage.md) đã kiểm chứng schema 27. [Bàn giao quyền đa máy](docs/phases/staff-handoff.md) đã kiểm chứng schema 28. Schema 29 có [ngưỡng đồng bộ/nhật ký đa cửa hàng/quản lý Web](docs/phases/store-settings-web-management.md); schema 30 hoàn thiện [archive audit và restore cloud](docs/phases/audit-archive-cloud-restore.md). Source 0.7.0+7 đã build/đóng gói và kiểm chứng local; chưa triển khai production. Bản 0.2.0-preview dùng schema 12; bản 0.1.0-preview cũ ở schema 9. Xem [tiến độ và giới hạn](docs/phases/progress.md) để phân biệt chức năng đã chạy với phần còn thiếu. Toàn bộ ứng dụng chưa nghiệm thu xong; chưa dùng cho dữ liệu thật. Kế hoạch: [quyết định kiến trúc](docs/architecture/decisions.md), [ERD](docs/database/erd.md). Đã có cloud staging riêng sau yêu cầu 17/11; xem docs/operations/staging-access.md. Chưa đưa vào production.

Mô phỏng 900 hóa đơn/ngày: [báo cáo tải](docs/phases/load-simulation.md). Đây là kiểm chứng trên SQLite và ước tính hạn mức, chưa phải số đo billing/CPU Cloudflare production.

Bản chạy thử mới schema 30: [Windows 0.7.0](artifacts/releases/ngoc-thanh-windows-0.7.0-preview.zip), [Android APK 0.7.0](artifacts/releases/ngoc-thanh-android-0.7.0-preview.apk), [Web/PWA 0.7.0](artifacts/releases/ngoc-thanh-web-0.7.0-preview.zip). Windows ZIP 66 file/Web ZIP 75 file manifest đã xác minh; APK v2/Internet/versionCode 7/ba ABI/API 24+ đạt, ký debug. [Phạm vi/giới hạn 0.7](docs/phases/preview-0.7.md). Kiểm tra lại: `./scripts/verify-release.ps1 -Version 0.7.0 -Schema 30`; đóng Web: `./scripts/package-web-preview.ps1`. Giải nén toàn bộ ZIP Windows rồi mở EXE; chỉ dùng dữ liệu thử. Web preview cũ giữ cấu hình riêng; đã có URL staging public tại docs/operations/staging-access.md. Các gói 0.6.0/schema 29 vẫn giữ nguyên trong artifacts/releases.

Bản thử local schema 21: [Windows portable 0.5.0](artifacts/releases/ngoc-thanh-windows-0.5.0-preview.zip), [Android APK 0.5.0](artifacts/releases/ngoc-thanh-android-0.5.0-preview.apk). Giải nén toàn bộ ZIP rồi mở EXE; APK ký debug. Xem [phạm vi bản 0.5.0](docs/phases/preview-0.5.md). Các file trong artifacts được Git bỏ qua, không tự đưa lên GitHub. Chỉ dùng dữ liệu thử; gói 0.5.0 cần API schema 21; preview 0.6.0 cần API schema 29; source 0.7.0 cần API schema 30. Gói 0.4.0 cũ vẫn giữ nguyên ở schema 18.

## Công cụ cần có
Flutter SDK trong PATH (script hỗ trợ SDK hiện có D:\development\flutter), Node 24+, Git. Windows cần Visual Studio C++ Desktop; Android cần SDK/JDK và thiết bị/emulator.

## Chạy local
```powershell
.\scripts\dev.ps1
# Web quản lý:
.\scripts\dev.ps1 -Target chrome
# Kiểm tra:
.\scripts\check.ps1
```
Lần đầu script cài dependencies và migrate D1 local. Cloud không cần để phát triển local. Copy .env.example thành .env để đặt cấu hình riêng; không commit secrets.

Lệnh độc lập:
```powershell
cd api
npm ci
npm run migrate:local
npm run dev
npm run typecheck
npm test
npm run build
```
```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release
flutter build web --release
```

## Quy ước
Feature theo thư mục; nghiệp vụ không nằm trong widget. Immutable records, typed payloads, kiểm tra input. SQL parameterized. Không sửa migration đã phát hành. Audit/outbox cùng transaction nghiệp vụ. Tiền không float. Không secret hard-code. Test tập trung invariant: kho, mã chứng từ, quyền, sync và restore. Đọc AGENTS.md trước thay đổi.

Mỗi phase cập nhật báo cáo trong docs/phases. Không push/deploy/kích hoạt phí khi chưa được phép.

Vận hành/triển khai/ký Android: [hướng dẫn](docs/operations/release-and-cloud-setup.md). Khôi phục SQL/bundle có dữ liệu lớn: `python scripts/cloud_restore.py PATH_SQL` hoặc thêm `--bundle` cho tar.gz đã giải mã; mặc định chỉ diễn tập local, không ghi cloud. Kiểm thử tooling: `python -m unittest discover -s scripts -p "test_cloud_*.py"` (Python 3.12+, GPG cho test mã hóa).

Mốc kiểm chứng 0.7 trước hotfix Web: 205 test Flutter đạt, flutter analyze sạch; 169 test API và 19 test backup/restore Python đạt. Đã build Windows/Web/Android, kiểm manifest/checksum và chữ ký APK v2. Đăng nhập nhận thông báo bàn giao thu hồi ngay quyền offline cũ, giữ hàng đợi; kiểm thử hồi quy đã đạt. Xem docs/phases/preview-0.7.md và docs/operations/release-and-cloud-setup.md.

Bổ sung đóng gói Windows: có bộ cài EXE tiếng Việt per-user, shortcut Start/gỡ Apps; ZIP kèm 10 DLL CRT Microsoft x64. Test cài/sửa/nâng/hạ phiên bản/chặn khóa/gỡ giữ dữ liệu fixture đã đạt. Xem [kết quả](docs/phases/windows-installer.md) và [cách dùng](docs/operations/windows-installer.md). Bộ cài tại [Windows setup 0.7.0](artifacts/releases/ngoc-thanh-windows-0.7.0-setup-preview.exe), chưa ký Authenticode.

Lượt kiểm chứng hai máy offline: 205 test Flutter toàn bộ đạt; analyze sạch. Đã kiểm tra hai file SQLite riêng, mất ACK rồi đóng/mở lại, gửi lại đúng UUID/nội dung, feed lặp không nhân đôi hóa đơn/tiền/kho và chặn dùng tồn của máy khác. Xem [báo cáo](docs/phases/two-device-recovery.md). Đây là protocol fixture, chưa thay nghiệm thu thiết bị/cloud thật. Mã sản phẩm và gói cài 0.7.0 không đổi.

Kiểm tra môi trường phát hành 17/11/2026: Git remote đọc được; Wrangler chưa đăng nhập Cloudflare; chưa có cấu hình production local/bộ biến ký Android, adb chưa có thiết bị. Bước cần chủ tài khoản làm trước được ghi tại [trạng thái môi trường](docs/operations/environment-status.md). Lượt này chỉ đọc và cập nhật tài liệu, không có build/test mới hoặc deploy.

Cập nhật cloud 17/11: [mở Web staging](https://ngoc-thanh-pos-staging.ngoc-thanh-161df6.workers.dev), [APK ký release 0.7.0](artifacts/releases/ngoc-thanh-android-0.7.0-release.apk), [Web staging ZIP](artifacts/releases/ngoc-thanh-web-0.7.0-staging.zip). [Đăng nhập chủ và sao lưu khóa ký](docs/operations/staging-access.md). API 176 test đạt; 14 HTTP checks thực và restore D1→D1 84 bảng/checksum/FK đạt. R2/billing và GitHub backup chưa bật; chưa nghiệm thu thiết bị thật. Xem [báo cáo](docs/phases/cloud-staging-release.md).

Cập nhật 18/11: [POS offline qua Cloudflare thật và khóa backup](docs/phases/native-cloud-e2e-backup-key.md). Native E2E đã đạt lost ACK/restart/replay, tồn 7, tổng thu 700.000đ, nợ 0; QA endpoint tắt sau kiểm thử. 23 test Python đạt; GPG private export được nhập vào keyring mới để giải mã/khôi phục đạt. [Khóa/public key và cách chủ giữ bản sao](docs/operations/owner-backup-key.md). R2 chưa kích hoạt, workflow chưa push vào repo public; backup định kỳ chưa chạy. Không có build app mới trong lượt này.

Hotfix Web 18/11: [ghi nhớ cấu hình đăng nhập](docs/phases/web-login-identity.md) đã lên staging. Lưu cặp ID sau login/enroll trong một record, tự điền khi mở lại, không ghi đè ID tự chọn và không lưu token/mật khẩu/quyền. 209 test Flutter toàn bộ đạt, analyze sạch; build/deploy/HTTPS hash và Chrome mobile đạt. [Hướng dẫn đăng nhập hiện hành](docs/operations/staging-access.md). API/native không đổi; chưa bật R2 hoặc push GitHub.

Rà soát nghiệm thu 18/11: [danh sách hiện hành](docs/phases/remaining-requested.md) đã thay backlog cũ, ánh xạ đủ các nhóm tính năng và ghi rõ R2/workflow/khóa độc lập/nghiệm thu còn thiếu. Lượt này chỉ kiểm tra trạng thái tài khoản và cập nhật tài liệu; không có code nghiệp vụ, deploy hoặc test mới.
