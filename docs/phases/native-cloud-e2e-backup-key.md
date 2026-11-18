# Chốt POS–cloud E2E và khóa backup — 18/11/2026

LEVEL 3. Tiếp nối E2E đã chạy ngày 17/11; ngày 18/11 đối chiếu hồ sơ và chuẩn bị/kiểm chứng khóa mã hóa. Không đổi mã nghiệp vụ/schema 30, không có bản cài mới trong phase này.

## POS offline qua Cloudflare thật

Worker/database ngoc-thanh-pos-e2e riêng, D1 UUID 8a3deced-6cfd-4a73-98e9-41f5b9cf3b62, không dùng staging bàn giao. Công cụ chuẩn bị đòi config QA/cờ thực thi, từ chối target staging. Token context được parent giữ trong môi trường/Windows DPAPI, không in log. Hai guard CLI được kiểm trong bộ API.

app/test/integration/cloud_e2e_worker.dart dùng hai SQLite thực, LocalService/CloudApi/SyncEngine thực và HTTPS tới Worker QA. Secure storage/installation ID được mô phỏng để tách hai thiết bị trên cùng máy; không mở credential store/SQLite người dùng. Network gate gây mất mạng hoặc bỏ phản hồi sau HTTP 200 của server thật.

Kết quả: enroll/approve/login, tạo biến thể và nhập 10+4; offline bán 3+4, máy B hết phân bổ bị chặn. Hai hóa đơn khác mã, đều số 001 của từng máy. Server commit nhưng ACK bị bỏ, outbox A giữ nguyên. Đóng/mở SQLite rồi gửi lại, replay feed và thu phần đặt cọc cùng command ID không nhân đôi.

Worker manual: 1 test đạt trong 01:00. Aggregate trực tiếp D1 xác nhận 2 hóa đơn/2 mã duy nhất, 3 payments/tổng 700.000 VND, ledger/cache 7, công nợ 0. Hai thiết bị native QA và mọi phiên đã thu hồi; admin logout, active sessions 0. Worker QA public tắt/trả 404; staging bàn giao vẫn 200. Không đưa giao dịch giả vào staging bàn giao. SQLite tạm được dọn khi đạt; lỗi giữ lại bằng chứng.

Hồ sơ artifacts/cloud-e2e-flutter.log và cloud-e2e-d1-aggregates.json. File worker không có hậu tố _test.dart nên CI/default Flutter test không tự ghi cloud. Flutter analyze cuối lượt sạch; lượt đầu phát hiện getter HttpOverrides và lint trong worker mới, đã sửa trước khi E2E đạt. Không có lỗi nghiệp vụ phải sửa.

## Khóa backup và khôi phục

GPG RSA 3072 ngoài repo, fingerprint 9CF7EAFBD6486A0B693BECE0F9FD92B791527F68; passphrase ngẫu nhiên được DPAPI bảo vệ, private export có passphrase. prepare_backup_key.py giữ export đã có, từ chối tự tạo khóa khác khi keyring mất/rỗng mà còn backup. Chỉ public key dùng cho pipeline.

Ngày 18/11 đã xuất D1 E2E thật (capture stdout để không công bố URL export tạm), nén/mã hóa bằng cloud_backup, nhập private export vào keyring tạm mới, giải mã và so checksum/verify_bundle/SQLite integrity/FK/ledger đạt. Giữ ciphertext ngoài repo, dọn SQL QA plaintext sau kiểm chứng; không upload private key/passphrase. Hồ sơ artifacts/cloud-backup-owner-key-drill.json.

23 test Python backup/restore/key guard đạt (19 hiện hành + 4 mới), có GPG thực và restore. Bộ API ở mốc E2E: 178 test/typecheck/lint đạt. Không chạy lại 205 test Flutter thường hoặc build gói vì không đổi mã sản phẩm; không ghi baseline thành lượt mới.

## Còn điều kiện bên ngoài

R2 kiểm lại 18/11 vẫn 10042/chưa kích hoạt, backup R2 chưa chạy. GitHub connector đọc được repo public dangchibao/DPHS_app nhưng workflow backup trên main trả 404. Chưa push/bật workflow hoặc thêm secrets theo AGENTS.md. Public key/fingerprint đã sẵn sàng; bucket/token R2 và việc xuất bản workflow còn thiếu.

Chủ cần sao lưu private key/passphrase và khóa Android độc lập ngoài máy, nghiệm thu phần cứng thật. Không coi tệp cùng ổ là backup độc lập. Xem ../operations/owner-backup-key.md và staging-access.md. Không cam kết chi phí luôn 0đ hoặc nghiệm thu production từ phép thử QA.

Đề xuất: không có tính năng ngoài yêu cầu.
