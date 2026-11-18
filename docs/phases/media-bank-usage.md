# Ảnh, QR và hạn mức cloud — LEVEL 2/3, schema 26–27

Đã có tài khoản/QR riêng cửa hàng, chủ cấu hình, thu ngân xem khi chuyển khoản. PNG/JPEG được đọc theo stream có giới hạn, nén QR PNG tối đa 64KB, không phóng lớn ảnh nhỏ, không ảnh động. Tiền ghi theo số thực nhận; QR tĩnh không tự điền nội dung/số tiền hoặc xác minh ngân hàng. Cấu hình, audit đã che số tài khoản còn 4 số cuối và outbox cùng transaction; API kiểm quyền hiện tại/quyền lúc cấp, store/device/user, JSON/ảnh và LWW. Ledger/quyền không dùng LWW.

Ảnh sản phẩm chung mọi size/màu, chọn/bỏ trong editor, hiển thị catalog/POS. Nén JPEG tối đa 1024px/200KB trên máy, chặn đầu vào trên 8MB/8 triệu pixel/ảnh động, bỏ EXIF/GPS/ICC/text bằng canvas RGB mới. SQLite chứa cache bytes có hash, nên đi cùng backup SQLite; catalog chỉ sync tham chiếu SHA256. Hàng đợi ảnh riêng, giữ nguyên khi lỗi/chưa bật R2, retry exponential backoff+jitter; chỉ chạy sau nghiệp vụ/audit, một ảnh mỗi lượt. Thanh đồng bộ nói rõ số ảnh còn lưu máy/chờ gửi.

R2 ảnh là tùy chọn, binding `IMAGES` vào bucket riêng tư, không dùng bucket backup. Worker kiểm JPEG/header/byte limit/checksum và danh tính; R2 put trước receipt D1. D1 metadata/feed/audit/ACK nguyên tử, mất ACK retry cùng ID không ghi trùng. Metadata được công bố sau upload rồi máy khác mới tải, tránh poll ảnh chưa tồn tại. Client kiểm SHA256 trước cache; ảnh lỗi không trở thành giao dịch tài chính bị lặp. Không có URL public đọc ảnh, GET cần phiên tương tác hợp lệ.

Màn Hạn mức cloud dành cho chủ có số account/ngày từ GraphQL Analytics tùy chọn và dung lượng POS từ D1 meta. Ngưỡng 80/100%, UTC reset 07:00 Việt Nam, cache 60s không qua ngày cũ, banner native mỗi 5 phút. Chưa có số đo không coi là 0; upstream lỗi/secret không lộ ra client. Budget hiển thị đổi được qua biến môi trường sau khi chủ đổi gói, không tự kích hoạt phí. CPU thực/account storage/R2 còn phải kiểm tra bằng công cụ Cloudflare. Runbook: cloud-usage.md.

Kiểm chứng: toàn bộ 191 test Flutter đạt, analyze sạch, Windows/Web release schema 27 build đạt. API 150 test toàn bộ đạt trước khi thêm luồng bàn giao, typecheck/lint/Worker dry-run đạt. Workerd HTTP với D1 và R2 **local** qua upload/replay/metadata global/download đúng byte ở chi nhánh khác/từ chối anonymous và sync bank account. 10 test backup đạt, gồm GPG thật và transport cloud mô phỏng; chưa có thao tác R2/Analytics/cloud thật. Chưa nghiệm thu chọn file/camera trên Android/iPhone thật.

Giới hạn vận hành: D1 backup chỉ chứa metadata ảnh R2; native backup có bytes ảnh đã cache. Không tự xóa object ảnh theo retention. Bucket ảnh phải được bảo vệ/backup riêng nếu chủ cần khôi phục cả kho ảnh khi mất bucket. Token actor đã thu hồi có thể cần người có quyền gửi lại ảnh, nhưng không mất bytes local. Gói preview 0.5.0 vẫn schema 21; chưa đóng gói source mới.

Đề xuất: không thêm ngoài phạm vi.
