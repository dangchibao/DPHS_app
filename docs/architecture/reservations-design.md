# Giữ hàng / đặt trước — thiết kế đã triển khai tại schema 17

DH kind=reservation, giá chỉ là báo giá; không ghi doanh thu, tiền thu hoặc stock_movements khi giữ. Số lượng giữ theo biến thể và quyền bán của máy; hàng còn khả dụng = quyền máy − lượng giữ đang hiệu lực. Tồn thực vẫn từ ledger kho. POS đặt cọc hiện tại là HD; không giả định đặt cọc DH nếu chưa có cầu nối tài chính.

reservation_lines: id,store_id,device_id,document_id(DH),variant_id,quantity,expires_at,created_at. resolution_events append-only: release/consume, related_document_id(HD khi giao), actor/reason/time; unique theo DH. Không lưu đè current_status, hết hạn được suy từ thời gian. Header DH giữ khách, số điện thoại, ngày hết hạn, snapshot giá/dòng. Khóa chính/mã sinh client như các chứng từ khác.

Tính hiệu lực ở một thời điểm t: created_at <= t < expires_at và chưa có resolution.created_at <= t. Dùng mốc thời gian của giao dịch trong trigger, tránh giải phóng ngược một lần giữ khi event tương lai đã đến server. Các query local truyền service.now để kiểm thử clock, không phụ thuộc trực tiếp CURRENT_TIMESTAMP.

Giữ/release/consume gắn máy lập DH để tránh hai máy offline cùng giao hàng giữ. Quản lý/thu ngân tạo và thu tiền; kho có thể xem/giải phóng giữ có lý do để xử lý kiểm kê. Backend kiểm tra quyền, nguồn máy, thời gian, số lượng và row scope.

Giao DH qua HD: đúng biến thể/số lượng đã giữ; HD giữ reservation_id; consume_event và hóa đơn/dòng/thanh toán/kho/audit/outbox trong cùng transaction. Consume ghi trước stock để guard không trừ quyền giữ lần nữa. Sau hết hạn tạo đơn bán mới bằng tồn khả dụng và giá hiện tại, không nhận consume quá hạn. Đơn đã consume/release không giao lại.

Update guard âm kho để giữ chỗ có hiệu lực bảo vệ cả POS, đổi hàng và điều chỉnh/điều chuyển. Local catalog/ComboPicker/POS hiển thị tồn thực, lượng giữ và khả dụng; SalesService và ReturnQuote kiểm tra quyền còn khả dụng. Điều chỉnh mất hàng đang giữ cần giải phóng giữ có lý do trước.

Outbox DH phụ thuộc catalog, customer/school và các biến động kho trước. HD/negative stock/release phụ thuộc giữ chỗ và các resolution trước; tránh giao dịch muộn đến cloud trước DH mà nó dựa vào. API batch đọc/ghi, dưới ngân sách 50 calls; partial ack 3 mutation. Restore tiếp tục chặn bán cho tới reconcile đủ giữ chỗ, expiry, hóa đơn và counter.

Test: giữ không trừ tồn thực; POS/đổi hàng không lấy phần đang giữ; hết hạn tự giải phóng; release không tạo kho giả; consume đúng một lần, atomic và không nhảy counter; hết hạn/thiếu quyền/máy khác bị chặn; replay/offline/cursor; mốc giờ trước/sau resolution và thứ tự causal.
