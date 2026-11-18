# Trạng thái môi trường phát hành — kiểm tra 17/11/2026

Cập nhật sau: đã hoàn tất Wrangler OAuth, deploy staging, tạo khóa Android/release và diễn tập D1 remote. Xem [trạng thái mới](staging-access.md). Các bảng bên dưới giữ kết quả trước khi đăng nhập, không phải điểm chặn hiện tại.

Đây là kết quả kiểm tra chỉ đọc tại thời điểm ghi nhận, không phải cấu hình tĩnh hoặc kết luận quyền tài khoản trong tương lai. Không in/lưu token, mật khẩu hoặc thông tin tài khoản vào báo cáo.

| Hạng mục | Kết quả thực tế |
| --- | --- |
| Cloudflare Wrangler | whoami chạy thành công nhưng báo chưa xác thực; cần đăng nhập |
| Biến môi trường Cloudflare | Tiến trình kiểm tra chưa đặt CLOUDFLARE_API_TOKEN/CLOUDFLARE_ACCOUNT_ID/D1_DATABASE_ID; không đọc giá trị file bí mật |
| Cấu hình production | Chưa có api/wrangler.production.local.jsonc; đã có mẫu production.example để điền sau khi xác định tài nguyên |
| GitHub/Git remote | origin đã cấu hình; git ls-remote origin thành công với chế độ không mở nhắc đăng nhập |
| GitHub CLI | Chưa có gh trong PATH; chưa kiểm quyền ghi, Actions hoặc secrets. Đọc được remote không chứng minh các quyền này |
| Android ký chính thức | Tiến trình kiểm tra chưa đặt đủ bộ biến ANDROID_KEYSTORE_PATH/PASSWORD/KEY_ALIAS/KEY_PASSWORD; chưa tìm/đọc khóa riêng của người dùng |
| Thiết bị Android | adb devices trả danh sách trống |

## Thao tác cần chủ tài khoản thực hiện trước

Mở PowerShell tại dự án:

```powershell
Set-Location D:\app\DPHS_app\api
npx --no-install wrangler login
```

Hoàn tất đăng nhập/cấp quyền tài khoản Cloudflare trong trình duyệt. Đây là thao tác chủ tài khoản phải thực hiện; không gửi mật khẩu, token hoặc mã xác minh qua chat. Lệnh dùng Wrangler đã cài trong api/node_modules, không cài thêm gói. Xem [tài liệu đăng nhập Wrangler](https://developers.cloudflare.com/workers/wrangler/commands/general/#login).

Sau khi đăng nhập, có thể kiểm tra lại bằng `npx --no-install wrangler whoami`. Việc đăng nhập không phải thao tác tạo database, deploy Worker, bật bucket hoặc mua gói. Các thao tác đó vẫn tuân theo phạm vi được phép của AGENTS.md; không tự thay production hoặc kích hoạt phí.

## Sau khi có xác thực

- Xác định tài khoản và D1 staging phù hợp bằng thao tác đọc; lập cấu hình local riêng, không sửa production đang chạy. Chuẩn bị migration/secret/bootstrap theo release-and-cloud-setup.md.
- Thiết lập GitHub Actions/secrets cho backup khi đã có quyền và tài nguyên cần thiết. Không cần đăng nhập GitHub lại chỉ vì gh chưa cài: Git remote hiện đọc được. Chưa push trong lượt kiểm tra này.
- Chủ giữ keystore ngoài repository và đặt các biến môi trường trên máy build khi chuẩn bị bản ký thật; không gửi khóa qua chat. Bản APK hiện tại vẫn là bản ký debug.
- Kết nối thiết bị thử khi nghiệm thu Android/HID/in PDF/đồng bộ thực. Test hai file SQLite và workerd local không thay thế phép thử phần cứng.

## Phạm vi lượt công việc này

Đã đối chiếu các nhóm nghiệp vụ và xác minh điểm chặn của môi trường. Không đổi mã sản phẩm, không có bản build mới, không chạy lại bộ kiểm thử không bị ảnh hưởng. Mốc kiểm thử gần nhất vẫn là 205 Flutter đạt/analyze sạch; 169 API và 19 Python theo các lượt đã ghi trong docs/phases. Không tạo tài nguyên cloud, không push, không bật Actions và không mở dữ liệu bán hàng thật.
