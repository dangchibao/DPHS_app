# Phần còn lại để vận hành — cập nhật 18/11/2026

Đây là trạng thái hiện hành, thay cho các backlog cũ được nối tiếp theo từng schema. Lịch sử và giới hạn của từng lượt vẫn nằm trong các báo cáo phase riêng. Bản chạy thử/source hiện hành thuộc họ 0.7.0+7, schema 30; chưa nghiệm thu production.

## Các nhóm tính năng đã triển khai

| Yêu cầu | Trạng thái/phạm vi | Hồ sơ |
| --- | --- | --- |
| POS | Tìm/quét HID, giỏ, size/màu, đơn vị, giảm giá, tiền mặt/chuyển khoản, cọc/giữ đơn tạm | [Bản chạy thử](preview-0.7.md) |
| Sản phẩm | CRUD/biến thể, size/màu/giá vốn/giá bán/SKU/barcode/năm học, ảnh cục bộ; ảnh cloud chờ R2 | [Ảnh và QR](media-bank-usage.md) |
| Kho | Nhập/điều chỉnh có lý do, ledger/cache, phân bổ theo máy và ngưỡng cảnh báo theo cửa hàng | [Đồng bộ ngưỡng](store-settings-web-management.md) |
| Mã vạch | Quét liên tục và tem PDF/khổ cấu hình; cần nghiệm thu HID/in thật | [Bản chạy thử](preview-0.7.md) |
| Hóa đơn | Snapshot, không sửa chứng từ đã phát hành, PDF/preview; adapter máy in theo phạm vi đã duyệt | [Bản chạy thử](preview-0.7.md) |
| Mã chứng từ | UUID client, CN/máy/ngày/counter cùng transaction, reset theo ngày và replay an toàn | [Hai máy cloud thật](native-cloud-e2e-backup-key.md) |
| Nhân viên/lương | Phân công/khóa/thay quyền, chấm công, cấu hình/chốt/hủy bảng lương, phiếu PDF; giữ lịch sử | [Lương](payroll.md), [bàn giao quyền](staff-handoff.md) |
| Đồng bộ | Outbox, batch/cursor, idempotence, backoff/quota, phân quyền API/local; tồn qua ledger | [Cloud E2E](native-cloud-e2e-backup-key.md) |
| Size | Ma trận size/màu, bảng quy đổi/gợi ý cấu hình theo chiều cao/cân nặng | [Size](size-rules.md) |
| Combo | Cấu hình thành phần/giá bộ, size riêng từng món, trừ kho thành phần, snapshot | [Combo](phase-5-combos.md) |
| Trường/lớp/học sinh | Danh mục/niên khóa, gắn hóa đơn, lịch sử mua, đơn tập thể | [Trường học](phase-5-schools.md) |
| May riêng | Số đo/yêu cầu, phụ thu cấu hình, hẹn trả/trạng thái, cọc và phiếu đo PDF | [May riêng](phase-6-tailoring.md) |
| Đổi trả | Theo hóa đơn gốc, lý do, trả/đổi/đổi size, cấn nợ/thu thêm/hoàn tiền, chứng từ mới | [Đổi trả](phase-6-returns.md) |
| Cọc/công nợ | Thu nhiều lần, lịch sử/quá hạn; thu offline ở máy lập chứng từ để tránh thu trùng | [Cloud E2E](native-cloud-e2e-backup-key.md) |
| Khuyến mãi | Combo/đầu năm/mua nhiều/voucher/bảng giá trường-đại lý, kiểm quy tắc cộng dồn | [Giá và ưu đãi](phase-5-commercial.md) |
| Giữ hàng | DH/giới hạn thời gian/tồn khả dụng/giao qua hóa đơn và giải phóng có lý do | [Giữ hàng](phase-6-reservations.md) |
| Báo cáo | Ngày/tháng, sản phẩm/size/tồn/may riêng/nợ/nhân viên/lãi gộp, lọc và Excel/PDF | [Local](reports-local.md), [cloud/Web](reports-cloud-web.md) |

Đa cửa hàng có [CK chuyển kho](transfers.md); quyền không dùng LWW. Audit có chain/receipt/checkpoint và [archive](audit-archive-cloud-restore.md), nhưng lưu R2 chưa kích hoạt. [Backup local](backup-upgrade-review.md), mã hóa, integrity/rotation/restore đối soát đã có. Cloud đã có Worker/Web staging và D1 APAC; Web quản lý online, không POS offline. Cấu hình/chốt/in lương thực hiện native với đối soát; Web có xem/dự tính theo quyền.

## Bằng chứng gần nhất

- 209 test Flutter toàn bộ/analyze sạch tại hotfix Web, build/deploy và Chrome mobile đạt: [báo cáo](web-login-identity.md).
- 178 test API/typecheck/lint ở mốc QA; 23 test Python backup/restore/key guard ở mốc chuẩn bị khóa. Các số thuộc những lượt riêng, không phải tất cả được chạy lại hôm nay.
- Native thật với hai file SQLite/HTTPS Cloudflare: lost ACK, restart/replay, 2 hóa đơn/2 mã, 3 payments/700.000 VND, ledger/cache 7, nợ 0. QA endpoint đã tắt, phiên đã thu hồi.
- Restore D1→D1 84 bảng/checksum/FK đạt. GPG private export đã nhập vào keyring mới để giải mã/khôi phục SQL QA thành công: [hồ sơ](native-cloud-e2e-backup-key.md).
- Windows có bộ cài/portable kèm CRT; Android có APK ký release và debug preview riêng. Chưa ký Authenticode Windows hoặc nghiệm thu phần cứng thật.

## Kiểm tra lại bộ bàn giao

Lượt tiếp tục ngày 18/11/2026: endpoint staging `/health` trả HTTP 200/schema 30. SHA256 của Windows setup/portable, Android release APK và Web staging ZIP đều khớp sidecar. Đây là kiểm tra tính toàn vẹn tệp, không thay cho chạy ứng dụng trên thiết bị sạch. `adb devices -l` không có thiết bị kết nối. R2 vẫn activation-required/10042, không phải lỗi đăng nhập. Workflow trả 404 ở lần kiểm tra trước khi được phép push; sau khi được phép riêng, source/workflow đã xuất bản main tại 97666f7. Lượt kiểm tra trước khi được cấp phép không thay cloud hoặc bật thanh toán. Sau đó, việc xuất bản và kiểm thử lại được ghi riêng trong github-publish-backup.md.
## Những việc chưa thể đánh dấu hoàn tất

1. **Kích hoạt R2 bằng tài khoản chủ.** Kiểm tra trực tiếp hiện vẫn trả 10042. Chưa có bucket riêng được cấu hình, nên ảnh cloud/archive audit/backup R2 chưa hoạt động. Chủ phải xem điều kiện kích hoạt và chi phí của nhà cung cấp; không tự bật subscription/thanh toán.
2. **Cấp cấu hình/secrets backup sau khi có R2.** Người dùng đã cho phép riêng và source/workflow đã push main tại commit `97666f7`; không còn chặn do quyền push hoặc thiếu file workflow. Cần bucket/S3 token/API token/public key đúng quyền trong Environment private-backup; không đưa private key lên Actions hoặc dùng OAuth Wrangler có thời hạn làm token backup dài hạn. Hai cờ lịch chưa bật. Xem [hồ sơ xuất bản](github-publish-backup.md).
3. **Bật lịch sau nghiệm thu backup thực.** Khi đủ điều kiện trên, chạy một lượt upload→download/hash→giải mã/restore rồi mới bật hai variable xác nhận lịch. Hiện không có bản backup R2 hằng đêm nào được công nhận; job skip hoặc key tạo trên cùng máy không thay thế backup độc lập.
4. **Bản sao khóa và thiết bị/tải thực.** Chủ cần giữ private key GPG, passphrase và keystore Android độc lập ngoài máy. Nghiệm thu Windows sạch/Android/iPhone/HID/in PDF và tải thực trước production; mô phỏng 900 hóa đơn/ngày vẫn sát ngân sách Free, không cam kết chi phí luôn 0đ.

Hướng dẫn hiện hành: [đăng nhập và khóa ký](../operations/staging-access.md), [khóa backup](../operations/owner-backup-key.md), [pipeline backup](../operations/cloud-backup.md). Bản staging là môi trường thử, không tự đổi sang production hoặc dùng database restore drill làm app.

Không có phase tính năng bổ sung nào được suy ra từ việc các điều kiện tài khoản/phần cứng chưa sẵn sàng. Chỉ mở công việc code tiếp khi có lỗi hoặc khoảng trống cụ thể trong phạm vi yêu cầu.

Đề xuất: không thêm tính năng ngoài danh sách đã duyệt.
