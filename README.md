# Đồng phục Ngọc Thanh

Phần mềm POS và kho đồng phục học sinh Việt Nam, nhiều cửa hàng/thiết bị, Windows và Android offline-first. Web/PWA quản lý/báo cáo online. Tiền nguyên VND, UI tiếng Việt.

## Stack
Flutter 3.50 / Dart 3.14, Riverpod, Drift/SQLite; Cloudflare Workers TypeScript + D1; pdf/printing. Không Firebase. GitHub Actions kiểm tra cả app/API.

## Trạng thái
Phase 0 đã kiểm chứng. Đã có lõi local sản phẩm/kho/RBAC, đồng bộ theo lô, POS/PDF/tem, đặt cọc/thu công nợ nhiều lần, sao lưu/khôi phục và nhật ký. Source schema 21 hiện có [trường/lớp/học sinh](docs/phases/phase-5-schools.md) và [combo](docs/phases/phase-5-combos.md), [giá riêng/khuyến mãi/đại lý](docs/phases/phase-5-commercial.md), [may riêng](docs/phases/phase-6-tailoring.md), [đổi trả/hủy HD](docs/phases/phase-6-returns.md), [giữ hàng có hạn](docs/phases/phase-6-reservations.md), [đăng ký máy/quản trị chi nhánh](docs/phases/phase-7-device-enrollment.md), [bảng size/gợi ý](docs/phases/size-rules.md), [chuyển kho CK](docs/phases/transfers.md), [chấm công/bảo vệ phiên](docs/phases/attendance-session.md). Bản 0.2.0-preview dùng schema 12; bản 0.1.0-preview cũ ở schema 9. Xem [tiến độ và giới hạn](docs/phases/progress.md) để phân biệt chức năng đã chạy với phần còn thiếu. Toàn bộ ứng dụng chưa nghiệm thu xong; chưa dùng cho dữ liệu thật. Kế hoạch: [quyết định kiến trúc](docs/architecture/decisions.md), [ERD](docs/database/erd.md). Không có kết nối production hoặc triển khai cloud.

Mô phỏng 900 hóa đơn/ngày: [báo cáo tải](docs/phases/load-simulation.md). Đây là kiểm chứng trên SQLite và ước tính hạn mức, chưa phải số đo billing/CPU Cloudflare production.

Bản thử local schema 21: [Windows portable 0.5.0](artifacts/releases/ngoc-thanh-windows-0.5.0-preview.zip), [Android APK 0.5.0](artifacts/releases/ngoc-thanh-android-0.5.0-preview.apk). Giải nén toàn bộ ZIP rồi mở EXE; APK ký debug. Xem [phạm vi bản 0.5.0](docs/phases/preview-0.5.md). Các file trong artifacts được Git bỏ qua, không tự đưa lên GitHub. Chỉ dùng dữ liệu thử; app/API phải tương thích schema 21. Gói 0.4.0 cũ vẫn giữ nguyên ở schema 18.

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
