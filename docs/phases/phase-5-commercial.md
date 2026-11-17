# Phase 5 — giá riêng, khuyến mãi và đại lý

Source schema 13, ngày 15/11/2026. Người dùng cho phép tiếp tục tự động; không cần duyệt giữa phase.

## Đã làm

- Bảng giá riêng theo biến thể, cửa hàng, trường hoặc nhóm phụ huynh/nhà trường/đại lý. Món không khai báo giữ giá chung. Chủ/quản lý tạo/sửa/ngừng; thu ngân chọn bảng giá khi thanh toán. Có danh bạ đại lý và chọn đại lý trên POS, tái sử dụng công nợ.
- Khuyến mãi giảm số tiền hoặc phần trăm (tối đa hai chữ số lẻ), ngưỡng tiền/số món, khoảng ngày theo giờ Việt Nam, trường/nhóm khách và voucher. Voucher dùng nhiều lần trong phạm vi điều kiện, không có cam kết dùng một lần hoặc giới hạn tổng lượt khi offline.
- Mỗi đơn tối đa một bảng giá và một khuyến mãi. Mặc định không kết hợp combo/bảng giá; chủ/quản lý phải bật rõ từng tùy chọn. Khuyến mãi không cộng giảm thủ công. Thu ngân được dùng mức giảm đã cấu hình, giới hạn giảm thủ công vẫn được kiểm tra riêng.
- Tiền tính bằng BigInt; phần trăm làm tròn xuống nguyên VND. Phân bổ giảm xuống dòng giữ đúng tổng. Kiểm tra tổng đang hiển thị trước commit, không âm tiền hoặc tràn safe integer.
- Hóa đơn/PDF giữ tên chương trình, bảng giá, số tiền giảm và revision. API tải lịch sử quy tắc đã duyệt, tính lại toàn bộ tiền và điều kiện, không tin số giảm/giá từ client. Revision đã duyệt vẫn xác minh được dù danh mục hiện tại đã đổi/ngừng; cùng revision khác nội dung bị chặn.
- Outbox có dependency bảng giá/đại lý/danh mục trước hóa đơn; lịch sử LWW thua cũng được lưu. Chặn chiếm ID khác cửa hàng, thu ngân tạo giá hoặc tự đổi loại khách để nhận giá đại lý.
- Sửa vòng đời controller khi đóng hộp thoại đang focus, chống kết quả tính giá bất đồng bộ cũ ghi đè lựa chọn mới, bố cục mobile không tràn dropdown.

## Kiểm chứng

74 test Flutter và 57 test API đạt; Flutter analyze, API typecheck/lint và Worker dry-run đạt. Có 15 vector tiền/điều kiện chung Dart/TypeScript; test giá lớn, phần trăm lẻ, ngày hết hạn, voucher, cộng dồn, snapshot/retry, rollback kho/counter và UI mobile.

Mô phỏng cơ sở 900 hóa đơn/ngày vẫn đạt, 92.340 lượt ghi ước tính; chưa mô phỏng mọi đơn cùng dùng đầy đủ ưu đãi hoặc đo CPU/billing D1 production.

## Chạy thử

`./scripts/dev.ps1` → menu **Bảng giá · khuyến mãi · đại lý**. Tạo bảng giá hoặc chương trình, chọn điều kiện và mức giảm. Tại thanh toán POS chọn học sinh/trường/đại lý nếu có, chọn bảng giá/chương trình, nhập voucher. Tổng tiền và số tiền đặt cọc tự tính lại; sai điều kiện sẽ chặn hoàn tất.

ZIP/APK 0.2.0-preview cũ dùng schema 12, chưa gồm chức năng này. Source schema 13 có thể chạy bằng script hoặc build lại. Chưa triển khai cloud.

## Giới hạn và đề xuất

Nếu danh mục học sinh chuyển sang trường khác trước khi hóa đơn offline được gửi, API kiểm tra lại liên kết hiện tại và giữ giao dịch để quản lý xử lý thay vì áp ưu đãi sai trường. Chưa có lịch sử enrollment đầy đủ. Không bổ sung tính năng ngoài danh sách đã duyệt.
