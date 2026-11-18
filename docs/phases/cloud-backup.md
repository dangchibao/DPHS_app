# Sao lưu cloud — LEVEL 3

Đã bổ sung workflow lịch 02:30 Việt Nam (mặc định chưa bật), script export D1 bằng Wrangler, restore vào SQLite tạm, kiểm integrity/FK/sổ kho, tar/gzip + manifest/hash, mã hóa GPG bằng public key và upload bucket R2 riêng. Tải lại ciphertext kiểm SHA256 trước xoay vòng 30 ngày/4 tuần/12 tháng. Có ngân sách dung lượng bucket; không upload/xóa khi preflight vượt ngân sách. Secret/private key không ghi vào code; workflow chỉ giữ báo cáo trạng thái an toàn, job lỗi để GitHub báo thất bại.

Đã chạy 10 test Python, gồm mã hóa/giải mã thật bằng cặp khóa fixture GPG và restore gói, checksum sai, SQL ATTACH/traversal, cache kho lệch/FK, không ghi đè đích và retention đúng prefix. Đã xuất SQL bằng Wrangler local từ snapshot SQLite của workerd schema 25 (tạo bằng SQLite backup API khi DB đang mở), chạy `drill-sql` thành công với dữ liệu HD/CK/lương/attendance thật từ smoke. Không chỉ kiểm exit export. Transport mock xác minh download/hash trước retention, HEAD sai không xóa bản cũ, budget thiếu không ghi R2.

Backup local đã có cảnh báo quá 2 ngày trong màn sao lưu, scheduler kiểm giải nén/khôi phục SQLite tạm mỗi 7 ngày, lịch đóng ngày/thoát/trước migration, rotation 7/4/12, checksum/integrity và khóa bán sau restore. Không viết lại các phần này.

Giới hạn: chưa có quyền/account để chạy export/upload/retention R2 thật; chưa kiểm chứng billing/export lock hoặc workflow GitHub thật. Chưa có importer cloud tự động xử lý dump có statement vượt 100KB; runbook yêu cầu dừng ở staging và dùng bind parameters có kiểm chứng. Khôi phục server về quá khứ vẫn cần đối soát toàn bộ thiết bị/cursor và giao dịch offline. Chưa gọi bước này là nghiệm thu production.

Runbook hiện hành: [sao lưu cloud và khôi phục](../operations/cloud-backup.md). Không kích hoạt workflow hoặc dịch vụ trả phí từ phiên này.

Đề xuất: không thêm ngoài phạm vi.
