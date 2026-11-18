# Báo cáo cloud và quản lý Web — LEVEL 3, schema 24–25

Schema 24 có `daily_reports`, receipt chống đếm trùng theo chứng từ/thanh toán, cache nợ hiện tại và rebuild dữ liệu cũ theo lô nhỏ. Worker cập nhật projection cùng transaction tiếp nhận ledger/ACK. Khách tính BigInt; tổng quá int64/blob quá ngân sách được đánh dấu không dùng được, không chặn giao dịch POS. API không xuất số bị làm tròn. Giá vốn/credit/thông tin trường/năm lấy snapshot.

Đọc báo cáo nhiều trang có lượt refresh theo feed cursor: thay thế các nhóm thay đổi trong một snapshot SQL, gồm cả nhóm mới nằm trước cursor trang. Không cộng delta lần nữa. Chủ có thể xem từng/tất cả cửa hàng; quản lý/kế toán chỉ scope hiện tại và quyền khi cấp phiên. Công nợ cloud là hiện tại, không giả là số cuối kỳ lịch sử; native có công nợ theo cutoff. Có kho, may và hiệu suất nhân viên; phân trang giới hạn dòng/byte, không tải cả ledger vào Worker.

Schema 25 thêm `devices.kind=native|web` bất biến. Chủ mời riêng trình duyệt, trình duyệt nhận mã và chủ duyệt như thiết bị khác. Mã sai loại bị chặn trước khi claim. Web login có phiên 8 giờ, chỉ giữ token RAM, không sync token/lease/SQLite. API allowlist chặn trình duyệt truy cập sync, checkpoint, ghi stock; trigger chặn cấp tồn cho Web, lọc khỏi đích CK và máy phải checkpoint lương.

Web hiện có báo cáo/dashboard, xuất Excel/PDF, nhân viên/phân quyền và quản trị cửa hàng/thiết bị. Những trang này dùng API thật, kiểm quyền server; không có POS offline. Đổi mật khẩu, catalog và lương native đã có nhưng chưa có giao diện đầy đủ trên Web. Không giả dữ liệu native thành cloud. Trình duyệt xác minh phiên mỗi 30 giây và khi quay lại app; 401 xóa phiên ngay, xác minh lỗi/mất mạng cũng xóa màn riêng tư. Chuyển phiên tháo Navigator con để đóng cả dialog. Không persist dữ liệu API/phiên vào SQLite/cache app.

Xuất báo cáo Web tạo `REPORT_EXPORT_REQUEST` idempotent trước khi tải file, không khẳng định người dùng đã lưu. Không gửi nội dung hàng/số lương vào audit xuất. Native vẫn xuất qua audit/outbox local.

Kiểm chứng schema 24: 177 test Flutter, 138 test API đạt; Windows/Web release build đạt. HTTP smoke trên workerd local qua toàn luồng đăng nhập/đăng ký/chuyển kho/lương và báo cáo, replay khác envelope không cộng trùng. Mô phỏng 900 hóa đơn/3 cửa hàng/10 máy được chạy lại, ước tính 96.483 rows written: không coi phần dư Free là an toàn vì chưa gồm mọi nghiệp vụ.

Kiểm chứng schema 25: 181 test Flutter toàn bộ, 140 test API, analyze/typecheck/lint và Worker dry-run đạt. Windows/Web release và D1 local migration 25 đạt. Smoke workerd local đầy đủ đạt. Chrome release thực tế đã đăng ký/duyệt trình duyệt, nhập mật khẩu/KDF, xem đúng doanh thu 100.000đ/lãi gộp 50.000đ, thu hồi thiết bị rồi màn riêng tư bị thay bằng đăng nhập. Đã xem ảnh chụp; form mobile 390×844 cũng được kiểm tra. Bộ `flutter test --platform chrome` bị kẹt iframe của harness; không báo bộ này đạt. Giao diện Web quản trị nhân viên/cửa hàng tái dùng các trang đã có, chưa nghiệm thu trên iPhone/iPad/Android thật.

Chưa deploy cloud, chưa push GitHub. Các gói preview 0.5.0 vẫn schema 21; source 0.6.0 đang phát triển, chưa đóng gói lại.

Đề xuất: không thêm ngoài phạm vi.
