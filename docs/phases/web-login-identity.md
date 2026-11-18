# Web ghi nhớ cấu hình đăng nhập — 18/11/2026

LEVEL 2. Sửa luồng đăng nhập Web/PWA hiện có, không đổi schema 30 hoặc quyền API.

Trước sửa, chỉ luồng enroll lưu ID cửa hàng/trình duyệt. Chủ đăng nhập bằng ID nhập trực tiếp không lưu lại cặp này. Khi connection đọc cấu hình cũ, nó còn có thể ghi đè ID người dùng vừa nhập.

Sau sửa, enroll và đăng nhập thành công lưu cặp store_id/device_id trong một bản ghi JSON theo API URL. Tải trang tự điền cấu hình nếu người dùng chưa nhập gì; không ghi đè chỉnh sửa hoặc dữ liệu của endpoint khác. Vẫn đọc hai khóa cũ để tương thích trình duyệt đã đăng ký. Chỉ hai ID được lưu, không lưu password/token/role/lease; phiên Web vẫn trong RAM và cần xác thực online.

Đã xử lý phản hồi đăng nhập đến sau khi màn hình đóng: bỏ token, không ghi metadata và không truy cập controller đã dispose. Enroll trình duyệt đã approved hiển thị thông báo đúng, không yêu cầu duyệt lại.

Bốn regression widget test mới đạt: đăng nhập trực tiếp→lưu cặp ID→mở lại vẫn cần mật khẩu; cấu hình cũ không ghi đè ID tự chọn; đăng nhập lỗi không ghi cấu hình; đóng màn hình trong khi login không nhận token/metadata muộn. Lượt test đầu cần sửa helper cuộn tới nút chưa được ListView tạo; sau sửa cả bốn đạt. Không giảm assertions hoặc quyền xác thực.

Flutter analyze sạch; toàn bộ 209 test Flutter đạt trong 02:22 (exit 0). Web release build đạt (301,9 giây), đã deploy đúng Worker staging. Version deploy 4b573fd9-0b2e-4856-9584-7d905656b0ce; SHA256 main.dart.js trên HTTPS khớp build 140f0bdb6a001944b51ddb843a4554082425885e9c3364aac3d6f96f5c3c052f. Health/schema 30, challenge/config xác thực và private route 401 đều đạt. Chrome profile riêng viewport 390×844 tải form đúng, không JS exception; screenshot đã xem trực quan. Browser thử được đóng bằng Browser.close. Không dùng mật khẩu chủ hoặc claim thiết bị owner trong phép thử browser. Native APK/EXE không build lại vì chỉ sửa Web. Nguồn: app/lib/features/web/web_portal.dart và app/test/web_identity_test.dart. Chưa có thay đổi nghiệp vụ native hoặc API; không yêu cầu migration dữ liệu.

Đề xuất: không có tính năng ngoài yêu cầu.

Đóng Web staging ZIP: 76 file manifest/hash đã xác minh, giữ nguyên bản preview cũ. Kiểm lại cuối lượt: R2 vẫn cần kích hoạt (10042), workflow backup trên main GitHub vẫn 404. Không push, không bật thanh toán; các điểm này không được ghi là đã hoàn tất.
