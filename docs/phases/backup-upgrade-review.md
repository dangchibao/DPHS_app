# Rà soát sao lưu trước nâng cấp — LEVEL 3

Sửa chọn đúng store/device từ danh tính bản cài khi tạo backup trước nâng cấp; với dữ liệu thử cũ ưu tiên CN01/A2 thay vì tùy ý lấy thiết bị đầu danh mục. Snapshot vẫn VACUUM INTO, checksum/integrity và mã hóa AES-GCM nếu đã cấu hình.

Mỗi backup nâng cấp có marker riêng chứa ID client, đường dẫn, checksum/bytes, thời gian, schema và chế độ mã hóa. Sau đăng nhập, scheduler hoặc lần backup tiếp theo đăng ký backup_runs + audit/outbox cùng transaction; xóa marker sau commit. Gọi lại không tạo bản ghi/audit trùng. Thiếu file hoặc sai checksum báo lỗi, không ghi lịch sử thành công giả.

Sao lưu thủ công/tự động/trước khôi phục đều kế thừa khóa cấu hình khi không truyền khóa riêng. Backup hiện trạng trước restore dùng cấu hình hiện hành, không lấy nhầm mật khẩu của file đang phục hồi. Máy mới vừa đăng ký nhưng chưa đăng nhập không tạo audit gán cho admin giả.

Marker dạng một file upgrade-backup.json từ bản thử cũ vẫn giữ nguyên trên ổ; chưa tự nhập lịch sử vì chỉ chứa tên file và thiếu checksum/danh tính đầy đủ. Có thể kiểm tra file qua màn sao lưu. Không xóa file backup cũ hoặc dữ liệu thật.

Test mới: tạo snapshot nâng cấp trên SQLite thật, đăng ký/audit đúng một lần; backup không truyền mật khẩu vẫn mở được bằng khóa cấu hình. Các test snapshot/restore/mã hóa cũ chạy lại. Kết quả cuối ở progress.md. Chưa có backup cloud hay khôi phục sang thiết bị mới.

Đề xuất: không thêm ngoài phạm vi.
