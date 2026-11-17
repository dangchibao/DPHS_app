# Phase 5 — mốc trường/lớp/học sinh

Đây là một phần của phase 5; combo, giá riêng, khuyến mãi/voucher vẫn còn phải làm. Người dùng đã duyệt tiếp tục tự động.

## Đã thực hiện

- Schema 10 chung Drift/D1: trường, lớp/niên khóa, học sinh và phụ huynh/khách trường. Có store_id, index theo cửa hàng, foreign key có phạm vi và LWW cho danh mục.
- Màn tiếng Việt thêm/sửa/ngừng theo dõi, tìm kiếm, xem lịch sử mua của học sinh. Chủ/quản lý sửa; thu ngân/kế toán được đọc theo quyền nghiệp vụ. Không xóa lịch sử.
- POS tìm học sinh hoặc chọn đơn tập thể. Dùng lại khách phụ huynh/khách trường, không tạo một khách mới cho mỗi lần mua. Snapshot trường/lớp/học sinh/niên khóa vào metadata hóa đơn và PDF; đổi danh mục không sửa hóa đơn cũ.
- Đơn tập thể đặt cọc/công nợ gắn đúng khách trường. Hàng đợi có dependency để trường/lớp/phụ huynh được gửi trước hóa đơn liên quan.
- Khởi tạo mới có hai trường, hai lớp và hai học sinh mẫu, ngoài 15 biến thể hàng đã có. Không tự thêm dữ liệu mẫu vào database cũ khi nâng cấp.
- Chặn dùng lại ID của cửa hàng khác, kể cả trong upsert LWW hoặc khi hai request tranh chấp. SQLite/D1 kiểm tra tham chiếu chứng từ, dòng, thanh toán, nợ, kho và audit cùng cửa hàng. Không chỉ dựa vào kiểm tra store_id ở giao diện.
- Tính tổng tiền bằng BigInt trước khi đổi sang số nguyên an toàn, chặn tràn số khi nhân giá lớn với số lượng.

## Kiểm chứng

- 25 test API đạt; typecheck và format đạt. Có test chặn ghi đè ID/foreign key chéo cửa hàng và giữ snapshot sau đổi tên trường.
- 4 test nghiệp vụ mới đạt: lịch sử/snapshot, khách trường/công nợ, rollback mã học sinh trùng/quyền thu ngân, giới hạn tổng tiền.
- 2 test POS mobile đạt: giỏ hàng và chọn học sinh/đúng phụ huynh/đóng hộp thanh toán không lỗi bố cục.
- Nhóm 13 test trường, auth/sync, backup và PDF đạt sau thêm seed. Các kiểm thử widget dùng SQLite được tách isolate để không chia sẻ vòng đời fake async giữa hai ca.
- Mô phỏng 900 hóa đơn/ngày vẫn đạt kiểm tra số liệu. Ước tính ghi bảo thủ hiện 94.140/100.000 rows/ngày, tính cả index; chưa là số đo D1 production. Hai index snapshot là partial index nhưng mô phỏng vẫn tính đầy đủ để không đánh giá thấp chi phí.

## Chạy thử

`./scripts/dev.ps1`, đăng nhập rồi mở menu → Trường · lớp · học sinh. Tạo trường, lớp, học sinh; tại POS chọn học sinh trong thanh toán hoặc chọn trường để lập đơn tập thể. Xem lại lịch sử tại danh sách học sinh.

ZIP/APK `0.1.0-preview` đã đóng gói trước mốc này, ở schema 9; chưa gồm màn trường/học sinh mới. Chạy từ source hoặc build lại theo README để kiểm tra schema 10. Chưa triển khai cloud và chưa nghiệm thu toàn bộ phần mềm.

## Đề xuất

Không có tính năng bổ sung ngoài phạm vi đã duyệt. Tiếp tục combo và quy tắc giá/khuyến mãi trước khi nghiệm thu toàn bộ phase 5.
