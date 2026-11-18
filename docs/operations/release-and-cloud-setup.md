# Chạy thử và chuẩn bị triển khai

Các gói trong artifacts/releases chỉ là bản chạy thử. Giao diện/tiền VND tiếng Việt; Windows/Android bán offline, Web chỉ quản lý online. Không push/deploy hoặc bật dịch vụ trả phí tự động.

Cập nhật 17/11 sau yêu cầu tiếp tục cloud: đã triển khai staging riêng và tạo APK ký release trên máy chủ. Đọc [truy cập staging và khóa ký](staging-access.md). Tài nguyên production đã có không bị thay đổi; R2/billing/GitHub backup chưa bật.

## Dùng bản chạy thử

Windows có thêm bộ cài EXE tiếng Việt per-user, shortcut Start và mục gỡ Apps; chi tiết tại [Bộ cài Windows](windows-installer.md). Gói mới kèm CRT app-local, không cần cài Visual Studio. Bộ cài chưa ký Authenticode và chưa nghiệm thu trên máy Windows sạch.

Windows: giải nén toàn bộ ZIP vào một thư mục, mở ngoc_thanh_pos.exe cùng DLL và data. Không chép riêng EXE, không mở hai phiên cùng database. Bản cài mới yêu cầu đặt mật khẩu quản trị; username admin. Khi chạy script dev, mật khẩu lấy từ .env. Không chứa mật khẩu mặc định trong bản build. Luôn giữ bản sao lưu trước khi nâng phiên bản.

Android: APK cần Android 7.0/API 24 trở lên, hiện ký debug để thử, chưa phải khóa ký phân phối do chủ giữ. Không gỡ app có dữ liệu thật chỉ để cài APK hoặc đổi chữ ký. Nếu hệ thống báo chữ ký khác, giữ nguyên dữ liệu và xử lý bản sao lưu/khóa ký trước. Chưa nghiệm thu Android hoặc máy quét/máy in/iPhone vật lý trong phiên này.

Web release đã build ở app/build/web. Có thể chạy local bằng ./scripts/dev.ps1 -Target chrome. Trình duyệt mới cần mã mời loại Web và chủ duyệt; đăng nhập giữ phiên RAM, mất xác minh hoặc thu hồi sẽ đóng cả route private. Không POS offline trong Web.

## Ký Android bằng khóa của chủ

Chuẩn bị keystore và bản sao an toàn ngoài repository. Không gửi private key/mật khẩu qua chat hoặc commit. Đặt đủ bốn biến môi trường:

`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

Đặt `ANDROID_REQUIRE_RELEASE_SIGNING=1` khi build phân phối để không dùng debug fallback. Sau đó build `flutter build apk --release`. Cấu hình thiếu một phần hoặc file không tồn tại sẽ dừng trước build, không lặng lẽ đổi sang debug. Không có khóa chủ thì các gói preview tiếp tục ghi rõ debug. Guard cấu hình thiếu đã được kiểm bằng Gradle offline; nhánh ký khóa chủ chưa chạy do chưa có khóa.

Lượt bổ sung sau đó đã tạo khóa release PKCS12 ngoài repo, build và kiểm chữ ký thật. Dùng `./scripts/build-signed-android.ps1` để tái sử dụng khóa này; sao lưu keystore/mật khẩu theo staging-access.md trước phân phối. Các gói preview debug trước đó vẫn được giữ riêng.

## Cloud/GitHub cần thông tin và phép riêng

Cần chủ chuẩn bị Cloudflare account, database/worker/domain đích, bucket R2 Standard private cho backup/audit, token tối thiểu, GPG public key và nơi giữ private key; secrets GitHub cho workflow. Không dán secrets vào chat. Nếu chỉ chạy local thì chưa cần các giá trị này.

Mẫu api/wrangler.production.example.jsonc phục vụ Web assets và API cùng một Worker. Copy sang wrangler.production.local.jsonc (đã ignore), thay UUID/name/origin đúng tài khoản. Mẫu mặc định production, không chứa secret, không tự tạo bucket. Thêm IMAGES tùy chọn và AUDIT_ARCHIVES sau khi xác minh private bucket/budget. Cấu hình static assets theo [Workers assets routing](https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/); các URL API được ưu tiên Worker để không bị trả nhầm trang SPA.

Chuẩn bị và kiểm trước khi xin phép thực thi:

```powershell
cd app
flutter build web --release
cd ../api
npm run lint
npm run typecheck
npm test
npx wrangler deploy --dry-run --config wrangler.production.local.jsonc
```

Dry-run không deploy. Khởi tạo owner một lần cần kế hoạch riêng với secret bootstrap do chủ đặt; không mở cloud với mật khẩu mẫu. Sau khởi tạo phải dùng production (bootstrap bị tắt), đổi mật khẩu và bỏ secret bootstrap. Không tự chuyển ENVIRONMENT để mở bootstrap trên một Worker đang chạy thật. Chỉ áp dụng migration remote, deploy, đăng ký máy thật hoặc bật workflow sau khi có phép riêng và dữ liệu mẫu/staging đã kiểm chứng.

Backup workflow và restore: cloud-backup.md, cloud-restore.md. Archive: audit-archives.md. Cấu hình usage: cloud-usage.md. Workflow mặc định chưa bật nếu thiếu biến xác nhận. Không có kết nối production sẵn trong gói.

## Trước nghiệm thu

Chạy thử trên máy Windows/Android dự kiến, HID thật, PDF/khổ giấy, mất mạng rồi nối lại hai thiết bị, bàn giao quyền, restore từ backup và lệch tồn chuyển kho. Giữ dữ liệu thử riêng. Cần đo D1 rows_read/rows_written và CPU, R2/Actions thực; mô phỏng 900 HD/ngày đang sát Free, không cam kết 0đ vô hạn hoặc an toàn ở tải đó. Không bật tính phí khi chưa duyệt riêng.
