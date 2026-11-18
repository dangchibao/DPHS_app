# Schema 30 — lưu trữ audit và công cụ khôi phục cloud

17/11/2026, LEVEL 3. App source 0.7.0+7, API tối thiểu/schema 30. Preview 0.6.0/schema 29 giữ nguyên.

Đã bổ sung manifest/receipt/checkpoint archive append-only, guard compaction sau gzip checksum/readback R2 private, quyền owner current+issued, tải file theo scope audit; chuỗi và replay tiếp tục đúng sau giảm log nóng. Native giữ local history, nhận head của chính máy qua login/directory. Có UI desktop/mobile: chuẩn bị, tiếp tục, xác nhận hoàn tất, hủy và tải file. Chưa cấu hình R2 thì không compaction.

Công cụ cloud_restore.py mặc định diễn tập local, hỗ trợ SQL hoặc bundle tar.gz đã giải mã. Bind parameters giữ TEXT/BLOB lớn và int64; schema whitelist theo migration, FK-order, triggers sau data, sequence high-water, checksum mọi bảng, FK/quick_check. Chỉ nhập target staging mới/trống khi có cờ xác nhận và quyền cloud riêng. Không deploy/bind/xóa/overwrite hay retry ghi mất ACK. Hướng dẫn: ../operations/audit-archives.md và ../operations/cloud-restore.md.

Kiểm chứng:

- 204 test Flutter toàn bộ đạt, analyze sạch; gồm nối head audit và UI lỗi upload/để sau/tiếp tục/xác nhận/quyền viewer.
- 169 test API đạt; typecheck/lint/Worker dry-run đạt. Có gzip/bomb/hash/metadata tamper, rollback D1, R2/readback lỗi, commit cạnh tranh/idempotent, chain âm/dương, replay cũ và khóa scope/quyền.
- 19 test Python backup/restore đạt, có GPG thật, dữ liệu >100KB/BLOB 200KB/int64 >2^53, FK vòng bị từ chối, target không trống/trùng nguồn, mất ACK không retry và checksum sai không chấp nhận.
- workerd/D1/R2 local đạt trọn luồng archive; export D1 sau archive được khôi phục integrity/FK/kho/checkpoint/receipt đạt. Importer đã chạy trên workerd D1 local với nguồn lớn: 83 bảng, 44 dòng, blob/int64/FK/cursor và checksum mọi bảng đạt. SQLite drill export D1 thật local: 84 bảng, 354 dòng đạt.
- Windows/Web/APK release 0.7.0 build cuối đã đạt; Windows ZIP 66 file/Web ZIP 75 file manifest/checksum và APK schema 30/v2/Internet/ba ABI đạt. Process kill schema 30 trước/sau commit kiểm chứng lại trọn lượt đạt. Chrome release đạt enrollment/duyệt/KDF login, báo cáo/catalog/lương/audit/archive desktop/mobile và thu hồi phiên ngay trên route private đã push; không lỗi JS. Ảnh màn hình đã kiểm tra trực quan tại artifacts.
- Mẫu cấu hình Workers phục vụ Web assets + API cùng origin đã dry-run. HTTP local chứng minh HTML/JS phục vụ đúng và các URL API private trả JSON401/no-store, không bị SPA che.

Mô phỏng cập nhật schema 30: 900 HD/ngày ước tính 99.183 lượt ghi/100.000 Free, chưa đủ headroom an toàn cho nghiệp vụ khác, backup hoặc compaction. Đã bỏ index audit_time dư thừa và dùng partial index riêng cho audit feed. Không coi estimate là billing/CPU production.

Giới hạn: cloud/GitHub chưa triển khai/chạy thật, chưa đo CPU/R2 quota; chưa ký APK bằng khóa do chủ giữ, chưa nghiệm thu nhiều máy native/máy in/HID/iPhone vật lý. File cold archive không nằm trong SQL backup, cần giữ bucket theo runbook. Thiết bị mất và dữ liệu phát sinh sau mốc backup phải đối soát, không tự coi sạch.

Đề xuất: không có tính năng ngoài phạm vi.

Bổ sung kiểm thử bảo mật bản 0.7: khi đăng nhập nhận STAFF_HANDOFF_PENDING, máy thu hồi ngay lease offline đã lưu và hết hạn phiên tương ứng, giữ nguyên hàng đợi/sync grant. Ngắt mạng sau phản hồi này không mở lại quyền cũ; phải xác thực online lại sau khi hoàn tất/hủy bàn giao. Kiểm thử hồi quy đã đạt trong bộ 204 test Flutter.
