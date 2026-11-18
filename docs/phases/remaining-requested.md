# Phần còn lại để vận hành — cập nhật 18/11/2026

Đây là trạng thái hiện hành, thay cho các backlog cũ được nối tiếp theo từng schema. Lịch sử và giới hạn của từng lượt vẫn nằm trong các báo cáo phase riêng. Bản chạy thử/source hiện hành thuộc họ 0.7.0+7, schema 30; chưa nghiệm thu production.

## Các nhóm tính năng đã triển khai

| Yêu cầu | Trạng thái/phạm vi | Hồ sơ |
| --- | --- | --- |
| POS | Tìm/quét HID, giỏ, size/màu, đơn vị, giảm giá, tiền mặt/chuyển khoản, cọc/giữ đơn tạm | [Bản chạy thử](preview-0.7.md) |
| Sản phẩm | CRUD/biến thể, size/màu/giá vốn/giá bán/SKU/barcode/năm học, ảnh cục bộ; cấu hình miễn phí không dùng ảnh cloud R2 | [Ảnh và QR](media-bank-usage.md) |
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

Đa cửa hàng có [CK chuyển kho](transfers.md); quyền không dùng LWW. Audit có chain/receipt/checkpoint và [archive](audit-archive-cloud-restore.md), nhưng cấu hình miễn phí không dùng R2, không xóa audit trong D1 để bỏ qua giới hạn. [Backup local](backup-upgrade-review.md), mã hóa, integrity/rotation/restore đối soát đã có. Cloud đã có Worker/Web staging và D1 APAC; Web quản lý online, không POS offline. Cấu hình/chốt/in lương thực hiện native với đối soát; Web có xem/dự tính theo quyền.

## Bằng chứng gần nhất

- 209 test Flutter toàn bộ/analyze sạch tại hotfix Web, build/deploy và Chrome mobile đạt: [báo cáo](web-login-identity.md).
- 178 test API/typecheck/lint ở mốc QA; 23 test Python backup/restore/key guard ở mốc chuẩn bị khóa. Các số thuộc những lượt riêng, không phải tất cả được chạy lại hôm nay.
- Native thật với hai file SQLite/HTTPS Cloudflare: lost ACK, restart/replay, 2 hóa đơn/2 mã, 3 payments/700.000 VND, ledger/cache 7, nợ 0. QA endpoint đã tắt, phiên đã thu hồi.
- Restore D1→D1 84 bảng/checksum/FK đạt. GPG private export đã nhập vào keyring mới để giải mã/khôi phục SQL QA thành công: [hồ sơ](native-cloud-e2e-backup-key.md).
- Windows có bộ cài/portable kèm CRT; Android có APK ký release và debug preview riêng. Chưa ký Authenticode Windows hoặc nghiệm thu phần cứng thật.

## Kiểm tra lại bộ bàn giao

Lượt tiếp tục ngày 18/11/2026: endpoint staging `/health` trả HTTP 200/schema 30. SHA256 của Windows setup/portable, Android release APK và Web staging ZIP đều khớp sidecar. Đây là kiểm tra tính toàn vẹn tệp, không thay cho chạy ứng dụng trên thiết bị sạch. `adb devices -l` không có thiết bị kết nối. R2 vẫn activation-required/10042, không phải lỗi đăng nhập. Workflow trả 404 ở lần kiểm tra trước khi được phép push; sau khi được phép riêng, source/workflow đã xuất bản main tại 97666f7. Lượt kiểm tra trước khi được cấp phép không thay cloud hoặc bật thanh toán. Sau đó, việc xuất bản và kiểm thử lại được ghi riêng trong github-publish-backup.md.
## Quyết định miễn phí và phần còn cần nghiệm thu

Người dùng đã bỏ phương án R2 vì không chấp nhận subscription/thanh toán. Không yêu cầu chủ kích hoạt R2 hoặc cấp R2 secrets nữa. Workflow R2 bỏ cron/khóa job; phương án thay thế là [backup D1 mã hóa về Windows](../operations/free-operation.md). Ảnh giữ cục bộ, audit giữ trong D1; Workers/D1 Free có hạn mức, khi hết thì giữ giao dịch chờ đồng bộ, không tự nâng gói.

1. **Bản sao độc lập ngoài máy:** giữ ciphertext/sidecar, private key GPG/passphrase và keystore Android ở nơi riêng do chủ kiểm soát. Backup trên cùng máy không bảo vệ khi mất cả máy và khóa. Chưa xác minh có USB/máy khác được bàn giao.
2. **Thiết bị và tải thực:** nghiệm thu Windows sạch/Android/iPhone/HID/in PDF trước production. Chưa có Android kết nối khi kiểm tra. Mô phỏng 900 hóa đơn/ngày vẫn sát ngân sách Free; không cam kết tải cloud vô hạn. Không tự xóa dữ liệu thật để giảm dung lượng.
3. **Giám sát backup và dung lượng:** theo dõi status/task result và D1 usage; máy phải bật/đăng nhập/có mạng. Lượt Task Scheduler đã kiểm chứng result 0, tạo ciphertext mới/checksum khớp. Lịch đặt 02:30/logon; chưa quan sát một đêm tự chạy. [Hồ sơ phương án miễn phí](free-operation.md), 37 test Python đạt.
Hướng dẫn hiện hành: [đăng nhập và khóa ký](../operations/staging-access.md), [khóa backup](../operations/owner-backup-key.md), [pipeline backup](../operations/cloud-backup.md). Bản staging là môi trường thử, không tự đổi sang production hoặc dùng database restore drill làm app.

Không có phase tính năng bổ sung nào được suy ra từ việc các điều kiện tài khoản/phần cứng chưa sẵn sàng. Chỉ mở công việc code tiếp khi có lỗi hoặc khoảng trống cụ thể trong phạm vi yêu cầu.

Đề xuất: không thêm tính năng ngoài danh sách đã duyệt.
