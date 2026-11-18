# Cloud staging, provision owner và ký Android — 17/11/2026

LEVEL 3. Người dùng đã báo đăng nhập Cloudflare và yêu cầu tiếp tục phần còn lại không hỏi thêm. CLI ban đầu chưa có phiên, đã chạy luồng Wrangler OAuth và nhận đăng nhập thành công. Đã dùng tài khoản duy nhất được xác thực để tạo môi trường thử riêng, không ghi đè Worker/database production đã có; không push GitHub hoặc kích hoạt subscription/billing.

## Đã hoàn tất và chạy thực tế

- D1 mới ngoc-thanh-pos-staging tại APAC, 30 migration remote đạt. Worker/Web tại https://ngoc-thanh-pos-staging.ngoc-thanh-161df6.workers.dev, ENVIRONMENT=production, SESSION_SECRET riêng, cùng origin và route API ưu tiên Worker. Web build release với API_URL tương ứng đạt, Worker deploy đạt; startup 1 ms theo deployment (không phải số đo CPU mỗi request).
- Công cụ provision owner chỉ trên DB trống, guard nguyên tử/rollback, không mở bootstrap HTTP. PBKDF2 ở Node, chỉ verifier trong D1, token/mật khẩu không in. Owner password ngẫu nhiên và SESSION_SECRET lưu Windows DPAPI ngoài repo. DB/Worker config local được Git ignore. Hai ID đăng nhập ban đầu ở staging-access.md; owner Web còn chưa claim.
- 14 kiểm tra HTTP thật đạt: health/schema, HTML Flutter, private API 401 JSON, bootstrap 403, client schema cũ 401, challenge/KDF/login, auth/me/role, management, report options/daily, Web không được push stock, logout rồi phiên mất hiệu lực. QA device và toàn bộ session QA đã thu hồi, có audit trong cùng batch. Không tạo hóa đơn hoặc nhập hàng thử vào app cloud.
- Xuất D1 thật, kiểm integrity/FK/ledger/schema local; import vào D1 mới ngoc-thanh-pos-restore-drill bằng REST chính thức: 84 bảng, 77 dòng ở thời điểm snapshot, 468 estimated writes, 27 write requests; mọi table checksum/count, foreign key và quick_check đạt. Target để unbound, không deploy hoặc bind vào app. Báo cáo artifacts/cloud-remote-restore-report.json. Đây là diễn tập thực trên tài khoản, không chỉ workerd.
- Export SQL được bảo vệ bằng Windows DPAPI ở LocalAppData/NgocThanhPOSDeployment/staging-export.sql.dpapi, giải mã lại/hash khớp trước khi dọn tệp export plaintext do lượt thử tạo. DPAPI SecureString có giới hạn độ dài nên lượt đầu dùng PSCredential cho SQL bị từ chối trước khi xóa; đã dùng ProtectedData cho bytes và kiểm chứng thành công. Owner password/keystore password ngắn vẫn dùng credential XML.
- Khóa Android RSA 3072/PKCS12 đã tạo ngoài repo, mật khẩu ngẫu nhiên được Windows mã hóa; build Android release thực với ANDROID_REQUIRE_RELEASE_SIGNING=1 đạt. APK chữ ký v2, DN Ngoc Thanh POS, certificate SHA256 16d6a8ab53070056791b81ed1b4d9ddd4f1996d6c9087179053f7c9cc6b6eb68. VersionCode 7/name 0.7.0, API 24+, Internet và ba ABI. Gói release/checksum/signing metadata riêng, giữ nguyên APK debug preview.
- Web staging ZIP đóng và xác minh 76 file manifest/hash. Bản preview Web cũ được giữ nguyên; gói staging đã gắn API_URL cloud nên khi chuyển origin cần build lại cấu hình phù hợp.
- Chrome headless với profile thử riêng đã mở URL HTTPS thật ở viewport 390×844: form đăng nhập tiếng Việt xuất hiện, API URL điền đúng và không có JS exception. Screenshot web-staging-public-mobile.png đã xem trực quan. Không đăng nhập/claim owner trong phép thử trình duyệt. Lần gọi CDP đầu nhanh hơn lúc Chrome mở cổng nên connection refused; chạy lại sau khi cổng sẵn sàng đạt và đóng đúng browser thử bằng Browser.close.

## Kiểm thử và lệnh

API: toàn bộ 176 test/42 file đạt, TypeScript/lint đạt. Có 7 test mới cho provision core/CLI. esbuild 0.28.2 là dev dependency rõ ràng để CLI bundle cùng source audit/security, không đưa provision CLI vào Worker bundle. npm audit tại lượt install báo 0 vulnerability. Format scripts MJS được CI lint hiện có kiểm tra.

Flutter không đổi mã nghiệp vụ; Web và Android release build đạt. Không chạy lại 205 test Flutter hoặc 19 Python trong lượt này vì không sửa các module đó; các số này là mốc trước. Công cụ Python restore hiện hành đã chạy local và remote thật như trên. PowerShell build-signed-android tạo key khi có cờ rõ ràng, không ghi đè key đã có, không fallback debug và phục hồi biến môi trường sau khi chạy.

Chạy lại các bước bằng hướng dẫn ../operations/provision-owner.md, ../operations/staging-access.md và ../operations/cloud-restore.md. Không chạy lại provision vào DB đang dùng. Không dùng database restore drill làm production hoặc sao chép danh tính native.

## Phần còn cần điều kiện ngoài môi trường

- R2 API trả 10042, tài khoản chưa bật R2. Không tự kích hoạt thanh toán; ảnh cloud/archive R2/backup R2 chưa hoạt động. GitHub backup workflow tiếp tục tắt cho đến khi bucket/private key/secrets/token dài hạn do chủ thiết lập đầy đủ. OAuth Wrangler không thay API token backup dài hạn.
- Chưa nghiệm thu Windows sạch, Android/HID/máy in/iPhone thật; chưa đo tải 900 HD/ngày/CPU/billing thực. 14 HTTP checks không chứng minh chịu được tải production; mô phỏng vẫn gần ngân sách Free.
- APK release mới cần sao lưu keystore và mật khẩu độc lập trước phân phối. DPAPI không bảo đảm giải mã sau khi đổi máy/cài lại Windows. APK khác chữ ký không thể update đè APK debug; không gỡ bản có dữ liệu thật để ép cài. Windows EXE chưa ký Authenticode. Không mua chứng thư/dịch vụ trả phí.

Đề xuất: không bổ sung tính năng ngoài yêu cầu.
