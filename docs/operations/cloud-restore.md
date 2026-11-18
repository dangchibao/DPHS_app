# Khôi phục D1 bằng bind parameters vào staging

LEVEL 3. `scripts/cloud_restore.py` giải quyết export có INSERT/JSON/BLOB lớn hơn giới hạn SQL import. Công cụ không deploy, đổi binding, xóa database, khôi phục đè hoặc tự mua/nâng gói. Mặc định chỉ diễn tập bằng SQLite tạm. Python 3.12+; không cần thư viện trả phí.

## Diễn tập trước

Sau tải ciphertext từ bucket backup và đối chiếu sidecar, giải mã GPG trên máy quản trị. Giữ private key/mật khẩu ở nơi riêng, không đưa lên GitHub/chat hoặc vào câu lệnh ghi log. Kiểm bundle rồi chạy:

```powershell
python scripts/cloud_restore.py D:\du-lieu-thu\backup.tar.gz --bundle
# Hoặc SQL đã lấy từ bundle được kiểm chứng:
python scripts/cloud_restore.py D:\du-lieu-thu\database.sql
```

Công cụ kiểm integrity đầy đủ trên SQLite tạm, foreign keys, kho/cache, metadata archive; so schema với migration dự án; kiểm chu kỳ FK và lịch sử migration. Chỉ gửi CREATE đã đối chiếu và INSERT với bind values. NULL là SQL NULL, int64 dùng chuỗi + CAST, BLOB dùng hex + unhex (kiểm khả năng trước ghi). Bảng được nhập theo phụ thuộc, documents theo original_id; trigger lắp sau dữ liệu để không cộng kho/cache hai lần. Giữ sqlite_sequence dù feed đã bớt log cũ.

Kết quả phải là `local_drill_verified`. So mẫu HD/MR/DT, công nợ, bảng lương và chain với nguồn. Diễn tập đã đạt với export D1 schema 30 và với TEXT >100KB, BLOB 200KB, số nguyên >2^53, FK tự tham chiếu và cursor 9999. Đã kiểm trên workerd/D1 local qua transport fixture riêng; ứng dụng production không có endpoint SQL tổng quát.

## Thao tác cloud cần chủ cho phép riêng

Chuẩn bị database D1 **mới, trống và chưa gắn ứng dụng**, khác database nguồn/production. Sao lưu hiện trạng và dừng ghi theo runbook cloud-backup.md. Đặt các giá trị bằng kênh quản trị an toàn, không dán token vào tài liệu hoặc chat:

- `CLOUDFLARE_ACCOUNT_ID`
- `D1_DATABASE_ID`: UUID nguồn/production để chống chọn nhầm
- `D1_RESTORE_TARGET_ID`: UUID staging mới
- `D1_RESTORE_API_TOKEN`: token quyền D1 Write tối thiểu trong account cần khôi phục

Chỉ sau khi chủ xác nhận đúng target mới chạy:

```powershell
python scripts/cloud_restore.py D:\du-lieu-thu\backup.tar.gz --bundle --execute-cloud --confirm-empty-target UUID_STAGING_MOI
```

Endpoint cố định là Cloudflare API chính thức, không theo redirect. Có giới hạn lô/bind/SQL/request, nhịp request có kiểm soát. Ngân sách mặc định 80.000 lượt ghi ước tính, có tính index và DDL; vượt thì dừng trước ghi. Đây không phải số đo billing hoặc phần Free còn lại của account. Chỉ đổi `--write-budget` sau khi chủ xem hạn mức/gói hiện có; không có tự nâng gói.

Mọi bảng được đọc lại bằng keyset, CAST integer ra text và hex BLOB để không mất chính xác ở JSON/JavaScript; so count/SHA256 với nguồn. So DDL, kiểm foreign keys và `PRAGMA quick_check` được D1 hỗ trợ. Kết quả cloud là `verified_unbound_target`, không phải đã phục hồi production. Nguồn SQLite vẫn được kiểm integrity đầy đủ; không báo D1 đã chạy `integrity_check` vì pragma đó không được D1 cho phép.

## Khi lỗi hoặc mất ACK

Không retry ghi tự động, không nhập tiếp mù, không tự xóa target nhập dở. Giữ target cách ly/chưa bind và log trạng thái; đối soát rồi dùng target mới khi được phép. Token/SQL/bind values không được in trong lỗi. Công cụ chưa hỗ trợ resume qua nhiều ngày quota. Chọn khoảng thời gian/ngân sách đủ trước khi bắt đầu; nếu Free không đủ thì giữ hệ thống offline hoặc lập phương án được chủ duyệt.

Trước dùng staging thay production, đối soát mọi thiết bị/outbox và giao dịch phát sinh sau mốc backup; backup cũ có thể thiếu dữ liệu mà máy đã nhận ACK. Cần khôi phục cả bucket audit/ảnh tương ứng, thu hồi các phiên cũ và duyệt lại thiết bị theo kế hoạch phục hồi. Không tự giải phóng quota kho của máy mất. Không chỉ đổi binding rồi bán tiếp. Khi thiếu máy, file hoặc chứng cứ thì chưa nghiệm thu.

Nguồn giao thức: [D1 query REST API](https://developers.cloudflare.com/api/resources/d1/subresources/database/methods/query/), [D1 limits](https://developers.cloudflare.com/d1/platform/limits/), [D1 PRAGMA hỗ trợ](https://developers.cloudflare.com/d1/sql-api/sql-statements/). Chưa thực thi nhập trên account cloud thật.
