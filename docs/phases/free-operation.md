# Chuyển sang vận hành không R2, không subscription — 18/11/2026

LEVEL 3: thay phương án sao lưu và cấu hình chi phí theo yêu cầu miễn phí toàn bộ của chủ. Không yêu cầu kích hoạt R2 nữa. Không thêm thẻ, checkout, đổi production hoặc bật dịch vụ trả phí.

## Đã thay đổi

- Workflow R2 cũ bỏ cron, job khóa false; giữ mã tham khảo, không chạy R2 dù có biến môi trường cũ.
- Backup D1 về Windows dùng scripts/free_d1_backup.py và free-backup-windows.ps1: export đã cho phép, restore SQL/integrity/FK/ledger/audit, bundle/checksum, GPG public-key encryption, exclusive write/fsync/readback, sidecar hoàn tất. Không gọi AWS/R2, không upload SQL hoặc private key lên GitHub.
- Lock chặn chạy chồng; không ghi đè ciphertext, không xóa backup cũ. Ngân sách mặc định 8 GB/database, đầy thì dừng và báo lỗi. Thư mục output bắt buộc ngoài repository, không qua symlink/junction.
- Cập nhật subprocess để chạy không mở console và đóng stdin khi không có input; giữ stdout/stderr riêng, không lộ nội dung export/credential khi lỗi. Wrapper không tự mở đăng nhập tương tác.
- Chọn ảnh cục bộ, audit giữ D1. Free quota hết thì giữ outbox và chờ; không nâng gói. Không thêm provider billing khác.

## Kiểm chứng thực

- 37 test Python đạt trong 41.237 giây (26 bài cũ và 11 bài mới); có GPG thật, không skip. Log artifacts/free-backup-tests-final.log.
- Backup staging schema 30 thật lúc 20:32:17 Việt Nam: ciphertext 14.727 byte, đọc lại SHA256 đạt; nhập private export vào keyring mới rồi giải mã/verify_bundle/integrity/FK/ledger đạt. Lần import thử đầu dùng thư mục dài hơn không đạt; thử lại keyring tạm ngắn đạt. Không công bố SQL/private key hoặc passphrase.
- Task Scheduler thật chạy lại lúc 20:43:32, tạo bản mới 20:43:33, ciphertext 14.752 byte, checksum khớp, State Ready và LastTaskResult=0 sau khi hoàn tất. Không coi chỉ đăng ký task là đã backup.
- Các lượt task dùng runtime Codex trước đó bị dừng với exit 0xC000013A; không công nhận. Đã chuyển task sang Python embeddable 3.14.10 độc lập, kiểm SHA256 ZIP theo python.org/chữ ký Valid, chạy ẩn và kiểm lại thành công. Không kết luận nguyên nhân dừng trước đó chỉ từ exit code. SQL/config tạm từ lượt dừng được dọn đúng đường dẫn sau khi có ciphertext mới đã xác minh; giữ cả hai bản backup mã hóa thành công.
- Task NgocThanhPOS-Free-D1-Backup-Staging: Interactive/Limited, 02:30 và khi đăng nhập; IgnoreNew/StartWhenAvailable. NextRunTime khi kiểm tra là 19/11/2026 02:30 Việt Nam. Đây là chạy thử task thành công, không phải đã quan sát một đêm theo lịch.
- Không đổi schema, logic bán hàng, API hoặc bản cài app; không deploy lại cloud trong phase này. CI/test app của phase trước vẫn là hồ sơ riêng, không gọi đó là lượt local mới.

## Giới hạn cần nói rõ

Máy phải bật, có mạng và tài khoản Windows đã đăng nhập; phiên Wrangler cần còn làm mới được. Runtime/repository cần giữ đúng đường dẫn. Backup nằm trên cùng máy chưa chống mất cả máy và khóa; chủ vẫn cần sao chép ciphertext/sidecar và giữ khóa/passphrase độc lập bằng thiết bị đang có. D1 backup không thay backup ảnh/SQLite từng máy.

Workers/D1 Free có hạn mức; không hứa tải/dung lượng vô hạn. Không tự xóa audit/chứng từ thật để làm vừa hạn mức. Chưa đo riêng billing của export; chưa thay account plan đã có. Cấu hình mới không tạo subscription hoặc mua thêm dịch vụ.

[Cách chạy/kiểm tra lịch và khôi phục](../operations/free-operation.md). Đề xuất: không thêm tính năng ngoài yêu cầu.
Bổ sung kiểm chứng cuối: lệnh Verify tái lập được từ wrapper, đã nhập private export vào keyring mới để giải mã/restore chính ciphertext do Task Scheduler tạo thành công. Ba test bổ sung chặn thiếu passphrase, trạng thái backup failed và ciphertext bị sửa trước khi đọc private key. Task vẫn Ready/result 0 sau kiểm tra cuối.
