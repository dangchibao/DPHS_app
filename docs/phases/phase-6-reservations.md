# Phase 6 — giữ hàng có hạn (schema 17)

DH là phiếu giữ/báo giá, không ghi tiền thu, doanh thu, công nợ hay xuất kho. Mã có chi nhánh/thiết bị/ngày; header, snapshot dòng, lượng giữ, audit và outbox cùng transaction. Tối đa 20 biến thể, giữ từ 1 phút đến 30 ngày; màn hình nhập số giờ. Giá bán được kiểm tra lại khi giao qua HD.

Tồn khả dụng máy = quyền bán máy − lượng giữ còn hiệu lực. Catalog/POS/combo hiển thị khả dụng; guard SQLite/D1 bảo vệ cả POS, đổi hàng và điều chỉnh âm. Tồn thực vẫn chỉ từ stock_movements. Hết hạn suy từ clock; release/consume append-only, một sự kiện kết thúc mỗi DH. Sự kiện ở tương lai không giải phóng tồn tại thời điểm quá khứ.

Thu ngân/chủ/quản lý tạo và giao DH; kho có thể xem/giải phóng có lý do. Giải phóng/giao offline chỉ trên thiết bị lập phiếu. HD phải giao đủ tất cả món giữ, đúng khách, còn hạn; cho phép thêm món. Ghi đủ dòng HD, consume rồi mới xuất kho trong cùng transaction. Lỗi bất kỳ rollback cả HD, tiền, consume, audit và bộ đếm. Gửi lặp không nhân đôi.

Outbox chứa DH trước HD; các thao tác kho/bán/giữ phụ thuộc nghiệp vụ đang chờ trước đó để giữ thứ tự causal. API kiểm tra quyền, scope, ngày, giá revision, số lượng, tổng, code, child append-only; không nhận thanh toán/công nợ trong DH. Pull nhận reservation_lines/events theo cursor hiện có.

Chạy `./scripts/dev.ps1` → menu **Giữ hàng · đặt trước** → tạo DH. Chọn **Giao hàng · thanh toán** mở POS với giỏ/khách đã giữ. **Giải phóng** yêu cầu lý do. Hết hạn cập nhật giao diện mỗi 30 giây; nghiệp vụ kiểm tra thời điểm ngay khi thực hiện, không chờ timer.

Đã kiểm chứng API: 93 test, typecheck/lint và Worker dry-run đạt; D1 local migration 17 đạt. Flutter toàn bộ 109 test ở mốc đầu; các ca rollback, hết hạn và UI bổ sung được báo tại progress.md sau khi chạy xong. Preview 0.3.0 vẫn ở schema 16, chưa có giữ hàng; chưa đóng gói lại hoặc deploy cloud.

Giới hạn: DH chưa thu cọc trực tiếp; đặt cọc hiện qua HD/MR. Không giao một phần DH; không chuyển quyền giao sang máy khác khi offline. Chưa nghiệm thu máy thật. Đề xuất: không thêm ngoài phạm vi.
