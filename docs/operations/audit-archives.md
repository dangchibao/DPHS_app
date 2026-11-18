# Kho nhật ký cũ

Schema 30 / app 0.7.0 trở lên. Chủ vào Nhật ký cloud → chọn cửa hàng → Kho nhật ký cũ. Quản lý chỉ xem/tải file cửa hàng mình; chỉ chủ có quyền hiện tại và quyền lúc cấp phiên được chuẩn bị/chốt/hủy lô.

Log gần đây giữ trong D1 ít nhất 90 ngày theo thời điểm server nhận, không theo đồng hồ máy. Mỗi lô tối đa 20 log, nguồn 192KB, gzip 194KB; lấy đoạn đầu liên tục của một chain thiết bị, phía ứng dụng hoặc API. Không nhảy qua log mới để tạo lỗ chain. Tra cứu online chỉ tìm log nóng; log cũ nằm trong file gzip và lịch sử local đã nhận trên thiết bị.

Ứng dụng lấy nguồn byte chuẩn bị từ server, kiểm checksum, nén ở client, gửi vào R2 private. Server giải nén có giới hạn, so nguồn/hash, ghi và đọc lại object để xác minh. Sau đó màn hình yêu cầu chủ hoàn tất đúng lô/số log. Nếu để sau, log D1 chưa giảm. Có thể tiếp tục hoặc hủy lô đang chờ. Không đủ bucket, quota, lỗi file hoặc lỗi transaction thì log vẫn giữ trong D1.

Transaction chốt ghi checkpoint và receipt nhỏ trước khi bỏ chi tiết nóng/bản sao audit trong feed. Trigger chỉ cho phép thao tác này qua guard lô verified; các API nghiệp vụ vẫn append-only. Receipt chống chèn lại/sửa log cũ qua envelope khác. Chain API âm và client dương tiếp tục từ mốc, không reset. Login/directory gửi mốc chain của chính thiết bị để máy không cấp lại số đã lưu trữ. Native không tự xóa lịch sử SQLite.

## Cấu hình khi chủ cho triển khai

Tạo/chọn bucket R2 Standard **private**, không gắn public domain, không bật r2.dev, không đặt lifecycle xóa các object audit. Thêm binding vào cấu hình đã duyệt:

```json
{"r2_buckets":[{"binding":"AUDIT_ARCHIVES","bucket_name":"TEN_BUCKET_PRIVATE_DA_DUYET"}]}
```

Không bật binding mặc định hoặc tạo dịch vụ qua script. R2 và tài khoản Free có hạn mức chung; bucket lưu trữ và backup cần cùng được giám sát. Không bật Infrequent Access hoặc dịch vụ có phí nếu chưa duyệt riêng. Manifest giữ key/hash cố định; API không có chức năng xóa file đã chốt. Script retention backup chỉ quản lý prefix backup riêng, không được trỏ vào prefix `audit/`.

## Khôi phục và kiểm chứng

Khôi phục D1 phải giữ audit_archives, audit_chain_checkpoints, audit_archive_receipts, processed_mutations và high-water server_seq; đồng thời giữ bucket cùng các object manifest tham chiếu. Backup SQL chỉ chứa metadata/checkpoint, **không chứa nội dung gzip trong R2**. Trước đổi binding phục hồi phải tải/kiểm checksum các object liên quan. File đã tải là JSON gzip UTF-8, chứa phạm vi, predecessor và toàn bộ log của lô.

cloud_backup.py kiểm quan hệ manifest/checkpoint/receipt khi diễn tập SQL. cloud_restore.py khôi phục nguyên các bảng này vào staging rồi so checksum từng bảng. Thiết bị đã nhận log cũ vẫn có thể xem local; không xóa cache/log của thiết bị để làm số khớp. Mất máy/file hoặc thiếu object phải xử lý trước nghiệm thu, không tự coi là đã đối soát.

Đã kiểm trên workerd/D1/R2 local: prepare/upload/readback/chốt lặp/tải đúng byte, lỗi rollback, replay đúng/sai nội dung và chain mới. Chưa chạy compaction trên cloud thật hoặc đo CPU/billing thật. Giới hạn CPU Free vẫn cần profiling; xem [Workers Web standards](https://developers.cloudflare.com/workers/runtime-apis/web-standards/).
