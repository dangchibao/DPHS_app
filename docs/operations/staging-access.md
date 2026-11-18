# Truy cập cloud chạy thử — 17/11/2026

Địa chỉ: https://ngoc-thanh-pos-staging.ngoc-thanh-161df6.workers.dev

Đây là môi trường thử độc lập, dùng D1 APAC schema 30; ENVIRONMENT=production để tắt bootstrap công khai. Không dùng dữ liệu bán hàng thật khi chưa nghiệm thu thiết bị/quy trình và hoàn tất backup cloud. Web/PWA quản lý online, không POS offline.

## Đăng nhập chủ lần đầu

Trên máy Windows đang phát triển dự án, mở PowerShell và tự xem mật khẩu đã được Windows mã hóa:

```powershell
$credential = Import-Clixml "$env:LOCALAPPDATA\NgocThanhPOSDeployment\staging-owner.credential.xml"
$credential.GetNetworkCredential().Password
```

Không gửi kết quả qua chat hoặc commit. Tài khoản là `admin`. Mật khẩu cloud được sinh ngẫu nhiên, không dùng mật khẩu mẫu hoặc mật khẩu phát triển. Tệp chỉ giải mã được với tài khoản Windows đã tạo nó; giữ bản sao an toàn độc lập khi bàn giao, trước khi cài lại Windows.

Ở trang đăng nhập:

- API đã điền địa chỉ cloud khi build; nếu trống, nhập đúng địa chỉ ở trên.
- ID cửa hàng: `store-cn01`.
- ID trình duyệt đầu tiên của chủ: `device-owner-web`.
- Nhập tài khoản/mật khẩu rồi đăng nhập. Trình duyệt này sẽ gắn với danh tính cài đặt đầu tiên; không dùng cùng ID cho trình duyệt hoặc thiết bị khác. Hai ID trên là cấu hình một lần, không phải mật khẩu.

Trình duyệt đầu tiên này chưa được claim khi bàn giao: các kiểm thử dùng thiết bị QA riêng, đã thu hồi cùng tất cả phiên QA. Đừng xóa storage của trình duyệt đã nhận danh tính mà chưa chuẩn bị thiết bị thay thế. Web giữ phiên trong RAM, tải lại vẫn cần đăng nhập. Sau khi enroll hoặc đăng nhập thành công (kể cả nhập ID trực tiếp), cặp ID được lưu cùng một bản ghi theo địa chỉ API và tự điền khi mở lại; không lưu mật khẩu/token/quyền. Cấu hình cũ vẫn được đọc, ID người dùng vừa tự nhập không bị ghi đè.

Sau đăng nhập, dùng **Cửa hàng · thiết bị** để mời máy Windows/Android hoặc trình duyệt tiếp theo. Mỗi thiết bị mới phải nhận mã đăng ký đúng loại, khai báo danh tính cài đặt riêng rồi được chủ duyệt. Không sao chép SQLite hoặc ID máy để tạo thêm máy bán hàng. Chỉ đưa hàng vào bán sau khi nhập kho và có phân bổ tồn phù hợp.

## Android đã ký release

Gói `artifacts/releases/ngoc-thanh-android-0.7.0-release.apk` được ký bằng khóa RSA mới tạo trên máy này; tách khỏi APK debug preview. Đây là chữ ký Android để cài/cập nhật, chưa phải việc phát hành Google Play hoặc nghiệm thu điện thoại thật.

Khóa nằm ngoài repository: `%LOCALAPPDATA%/NgocThanhPOSDeployment/android-release/ngoc-thanh-release.p12`. Mật khẩu/alias nằm trong `signing-password.credential.xml` cùng thư mục, được bảo vệ bằng Windows DPAPI. **Trước khi phân phối, sao lưu keystore và mật khẩu độc lập ở nơi an toàn do chủ giữ.** Chỉ chép tệp XML sang máy Windows khác không bảo đảm giải mã được; mất khóa sẽ mất khả năng ký bản cập nhật tương thích.

Xem mật khẩu bằng PowerShell trên máy/tài khoản này khi tự sao lưu, không gửi qua chat:

```powershell
$signing = Import-Clixml "$env:LOCALAPPDATA\NgocThanhPOSDeployment\android-release\signing-password.credential.xml"
$signing.UserName
$signing.GetNetworkCredential().Password
```

Build lại dùng `./scripts/build-signed-android.ps1`; tạo khóa mới lần đầu cần cờ rõ ràng `-CreateSigningKey`. Tệp đã có không bị ghi đè hoặc tự thay khóa. Có thể tiếp tục dùng đủ bốn biến môi trường Android với keystore của chủ thay cho kho được tạo trên máy này. APK khác chữ ký không cập nhật đè được bản debug đang cài: không gỡ app có dữ liệu thật để ép cài; xử lý backup/khóa ký trước.

## Kiểm chứng và phần còn cần bên ngoài

- 14 kiểm tra HTTP thực đã đạt: HTML, health/schema 30, API private không bị SPA thay thế, bootstrap bị chặn, client cũ bị chặn, challenge/KDF/login owner, quyền Web, management/reports, logout/thu hồi. Owner browser đầu tiên còn chưa claim.
- Chrome đã tải bản HTTPS thật ở viewport mobile, hiển thị form đăng nhập/API URL và không có lỗi JS; screenshot được kiểm tra trực quan. Đây không thay thế nghiệm thu iPhone/Android thật.
- SQL xuất từ D1 thật đã qua integrity/FK/ledger trên SQLite và import lại vào D1 drill độc lập: 84 bảng, 77 dòng ở thời điểm snapshot, checksum từng bảng/FK/quick_check đạt. Database drill không gắn Worker, không phải database của app và không được tự thay vào app. Nó chứa snapshot thử, giữ cách ly. Đây không phải lịch sao lưu tự động.
- R2 đang chưa kích hoạt, API trả code 10042. Không bật thanh toán/subscription. Ảnh cloud, archive audit R2 và backup R2 tự động chưa hoạt động; dữ liệu hot trong D1 và ảnh cục bộ vẫn có cơ chế hiện hành. Chủ cần tự quyết định kích hoạt R2 và phương thức thanh toán nếu muốn dùng; không có cam kết 0đ vô hạn.
- GitHub source/workflow đã push main ngày 18/11 sau khi người dùng cho phép riêng; lịch backup chưa bật. Cần bucket private, public key GPG do chủ giữ private key và GitHub Environment Secrets/token quyền tối thiểu; không dùng OAuth token Wrangler có thời hạn làm secret backup dài hạn. Xem ../phases/github-publish-backup.md.
- Chưa ký Authenticode cho Windows, chưa nghiệm thu Windows sạch/HID/máy in/Android/iPhone vật lý. Không kích hoạt dịch vụ trả phí hoặc sửa tài nguyên production đã có.

Tham khảo [R2 bắt đầu sử dụng](https://developers.cloudflare.com/r2/get-started/) và [Workers Free pricing](https://developers.cloudflare.com/workers/platform/pricing/). Không thay hoặc xóa private files/khóa ký để chạy lại setup.
