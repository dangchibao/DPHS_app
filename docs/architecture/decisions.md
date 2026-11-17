# Kế hoạch được duyệt — 15/11/2026

## Phạm vi
POS đồng phục học sinh Việt Nam: sản phẩm/size/màu, kho theo chi nhánh, combo, trường/lớp/học sinh, may riêng, đổi trả, giữ hàng, đặt cọc/công nợ, nhân sự/lương, báo cáo, audit, backup. Người dùng duyệt toàn bộ phương án và cho phép tiếp tục không dừng giữa phase.

## Kiến trúc
Flutter Windows/Android → Riverpod → nghiệp vụ → Drift/SQLite → outbox → Workers TypeScript → D1. Web/PWA chỉ quản lý online. PDF/Excel/ảnh xử lý client. R2 chỉ ảnh và backup mã hóa khi có cấu hình, không bật dịch vụ trả phí.

## Ràng buộc
- Tiền nguyên; API kiểm tra safe integer; ngày chứng từ Asia/Ho_Chi_Minh.
- UUID client; code TYPE-CN-DEVICE-YYYYMMDD-NNN; counter cùng transaction. Mã thiết bị không tái sử dụng.
- stock_movements append-only; stock_balances cache. Không trực tiếp sửa tồn. Phân bổ tồn bán offline theo thiết bị để không oversell.
- Hóa đơn đã phát hành bất biến; trạng thái là event, điều chỉnh bằng chứng từ mới.
- RBAC cả local và API; quyền và tài khoản chỉ sửa online. Quyền offline đã cấp có hạn 7 ngày, thu hồi có hiệu lực khi thiết bị nhận được.
- Danh mục dùng chung không có store_id; bảng nghiệp vụ có store_id và index bắt đầu store_id. Ngoại lệ hệ thống được ghi rõ.
- LWW chỉ danh mục; quyền server quản lý; kho cộng/trừ theo ID giao dịch. Đồng hồ lệch phải phát hiện; tie-break deterministic.
- Đơn vị sync nguyên tử gồm chứng từ + dòng + kho + thanh toán + audit. Batch retry idempotent. Cùng ID khác nội dung bị từ chối.
- Audit hash chain theo thiết bị, checkpoint cloud; không tuyên bố bảo vệ trước người có toàn quyền hệ điều hành.
- Backup dùng SQLite backup/VACUUM INTO, integrity + SHA256; restore khóa bán tới khi reconcile cloud/counter/device allocation.

## Phase
0 khung/CI/tài liệu/design; 1 local/RBAC/catalog/kho/audit; 2 sync/quota/load; 3 POS/barcode/PDF; 4 backup/audit UI; 5 combo/trường/khuyến mãi/công nợ; 6 may/đổi trả/giữ/chuyển kho; 7 lương/báo cáo; 8 tích hợp/đóng gói/tài liệu.

## Hạn mức (kiểm chứng 15/11/2026)
Workers Free 100000 request/ngày, 10ms CPU/request. D1 5M read/ngày, 100K write/ngày, 500MB/database, 5GB/account. Time Travel 7 ngày. Reset 00:00 UTC = 07:00 Việt Nam.
Nguồn: https://developers.cloudflare.com/workers/platform/limits/ ; https://developers.cloudflare.com/d1/platform/pricing/ ; https://developers.cloudflare.com/d1/platform/limits/

Ước tính 900 hóa đơn/ngày × 4 dòng, 10 thiết bị/12 giờ: 9000–15000 request, 0.3–1M reads, 55–95K writes gồm index. Chưa phải benchmark; phải đo ở phase2 và nêu rõ trường hợp vượt. Audit 3000 log/ngày × 1KB × 90 ngày ≈270MB payload, chưa index. Không cam kết miễn phí vô hạn.

D1 export có thể block truy vấn; thực hiện ngoài giờ. Chưa xác nhận phí rows read export: đo analytics trước/sau trên môi trường thử. R2 Standard free 10GB-month, phải tính cả rotation backup và ảnh.

## Đăng nhập bootstrap
Username admin, password người dùng cung cấp qua biến môi trường, không lưu trong repository/binary. Không dùng tài khoản demo như một cửa hậu. Yêu cầu đổi mật khẩu trước sử dụng thực tế.

## Xác thực dưới hạn mức CPU Workers

Client thực hiện PBKDF2-SHA256 600.000 vòng với salt cloud riêng qua challenge. Worker chỉ SHA-256 lớp ngoài và so sánh; D1 giữ `client-v1:hash`, không giữ credential gửi đăng nhập. Đăng nhập/tạo nhân viên/đổi mật khẩu dùng cùng giao thức; mật khẩu local dùng salt và verifier riêng. Credential có giá trị như mật khẩu, cần HTTPS trên môi trường thật, không ghi vào audit/log. Bootstrap nhận mật khẩu môi trường chỉ ở development; provisioning production phải thực hiện bằng công cụ quản trị trước triển khai. Credential legacy được nâng cấp nhanh sau đăng nhập development thành công; production không nhận legacy.

Kiểm thử Dart đối chiếu vector PBKDF2 từ Node crypto, bao gồm khoảng trắng mật khẩu. Kiểm thử API chứng minh hash lưu trong DB không dùng làm credential và phiên cũ bị thu hồi sau đổi mật khẩu. Chưa thay thế kiểm tra thực tế CPU Workers bằng kết quả Node/SQLite local.

## D1 Free: query và đối số SQL

Đối chiếu lại https://developers.cloudflare.com/d1/platform/limits/ ngày 15/11/2026: 50 query/lượt Worker, 100 bind/query, tối đa 32 đối số/hàm SQL; db.batch tính một query cho giới hạn lượt gọi. Cấu hình ở api/src/config.ts. API vẫn nhận payload cũ tối đa 5 mutation nhưng mỗi lượt xử lý/ack tối đa 3; client mới gửi 3. Bản ghi chưa ack được giữ nguyên trong outbox.

Đọc các dòng trả/hàng thay thế và loại khách theo batch để số D1 calls không tăng theo số dòng. JSON audit có 18 trường: dùng json_object tối đa 16 cặp rồi json_set các trường còn lại, giữ cả null. Test mô phỏng giới hạn 50 lượt gọi và 32 đối số; không thay thế đo CPU/billing production.

Ngoại lệ sửa cú pháp migration 0006: thay json_object 36 đối số bằng json_object + json_set tương đương để lần khởi tạo D1 mới cũng hợp giới hạn. Không thay bảng/cột/nội dung chứng từ. Migration 0016 thay trigger tương tự cho database đã cài bản cũ; các file SQL API/Drift vẫn khớp từng byte. Chưa có cloud production được triển khai. Đây là sửa lỗi tương thích cần thiết, không dùng cách sửa lịch sử để nâng schema database đã chạy.
