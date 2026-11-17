# Quản trị cửa hàng và đăng ký thiết bị — schema 18

Đã có API và giao diện native online dành cho chủ: tạo chi nhánh (ID UUIDv7 client), mời máy mới, hiển thị mã đăng ký một lần trong 1 giờ, duyệt máy đã nhận mã và thu hồi máy. Mã máy duy nhất toàn hệ thống, không tái sử dụng. Thu hồi là trạng thái kết thúc; DB bảo vệ identity và installation binding không được ghi đè. Không tự thu hồi máy đang quản trị.

Mã đăng ký lưu hash ở bảng private device_enrollments; token chỉ trả một lần và không vào audit/feed. Public endpoint nhận mã và installation_id, chỉ gắn một bản cài; gửi lại cùng bản cài được chấp nhận, bản cài khác bị chặn. Đăng ký giữ trạng thái pending; chủ phải duyệt riêng. API kiểm tra cả vai trò hiện tại và vai trò lúc cấp phiên. Mọi thao tác quản trị và lần gắn máy đầu có audit; không đưa credential/hash mật khẩu vào màn tổng quan.

App mới chưa có dữ liệu có nút **Kết nối chi nhánh · đăng ký máy mới** trên Windows/Android. Nhập API HTTPS và mã từ chủ. Lưu store/device/endpoint/installation hash trong local_settings; không lưu token đăng ký. Provider khởi động đúng danh tính này, không seed CN01 lên máy vừa đăng ký. Sau khi chủ duyệt, tài khoản được phân công đăng nhập online lần đầu để cache quyền offline. Đăng nhập API thành công cập nhật pending local thành approved. Header workspace hiển thị đúng chi nhánh/máy.

Máy có người dùng hoặc outbox không được thay danh tính qua bước này. Khôi phục/bản sao máy tiếp tục bị installation binding và reconcile bảo vệ. Máy mới chưa có phân bổ hàng nên không có quyền bán tồn của máy khác; không tự cấp lại quyền tồn chỉ vì đăng ký thành công.

Chủ có thể gán nhân viên đã có sang chi nhánh mới; không tự xóa phân công cũ. Sửa vai trò/khóa nhân viên hiện có dùng màn nhân viên. Bàn giao thực sự giữa chi nhánh, xử lý giao dịch offline chưa đồng bộ và phân bổ/chuyển tồn vẫn cần hoàn thiện; không tuyên bố đã có toàn bộ vận hành đa cửa hàng.

Thu hồi cloud không thể liên lạc ngay với máy đang mất mạng. Máy biết khi kết nối lại hoặc lease 7 ngày hết hạn. Phải đồng bộ hết giao dịch trước khi thu hồi; hàng đợi chưa gửi giữ trên máy, không tự xóa. Chưa có tái phân bổ quyền tồn của máy mất.

Kiểm chứng: API 96 test, typecheck, Worker dry-run; D1 local migration 18 đạt. UI tạo chi nhánh và bước đăng ký trên mobile đạt. Test enrollment bảo vệ bản cài có dữ liệu, endpoint/danh tính/token và pending → approved đạt; số test tích hợp cuối ghi trong progress.md. Không deploy cloud, không push GitHub. Preview 0.3.0 cũ vẫn schema 16.

Chạy source `./scripts/dev.ps1`, đăng nhập online bằng chủ → **Cửa hàng · thiết bị**. Tạo CN02, mời máy B3, dùng mã trên bản cài trống → tải lại danh sách → duyệt. Phân công người dùng đã có vào CN02. Production vẫn cần quy trình provision chủ đầu tiên và tài khoản Cloudflare; chưa yêu cầu chủ thao tác vì chưa đến bước triển khai.

Đề xuất: không thêm ngoài phạm vi.
