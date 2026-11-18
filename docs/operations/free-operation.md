# Vận hành không đăng ký dịch vụ trả phí

Quyết định hiện hành ngày 18/11/2026, thay cho phương án yêu cầu kích hoạt R2. Không thêm thẻ, không checkout R2, không nâng gói Workers/D1. Không dùng Firebase hoặc chuyển sang một dịch vụ yêu cầu billing khác. Chi phí dịch vụ mới của cấu hình này là 0đ trong hạn mức Free; không hứa cloud có dung lượng/tải vô hạn. Máy, Internet và thiết bị lưu trữ do cửa hàng sử dụng sẵn.

## Phạm vi

- Windows/Android bán offline bằng SQLite như hiện hành. Workers/D1 Free chỉ đồng bộ và quản lý online; hết hạn mức thì giữ outbox và thử lại có kiểm soát, không tự mua thêm. Web/PWA vẫn cần mạng.
- Ảnh sản phẩm lưu trên máy và đi cùng backup local; không có đồng bộ ảnh giữa các máy qua R2. QR ngân hàng nhỏ đã có cơ chế hiện hành, không yêu cầu bucket ảnh.
- Audit vẫn giữ trong D1 và backup D1; không xóa log để giảm dung lượng khi chưa có archive được xác minh. R2 audit archive không dùng trong cấu hình này. Phải theo dõi tổng dung lượng D1 vì lịch sử tiếp tục tăng.
- Workflow R2 cũ đã bỏ lịch cron và đặt job `if: false`; không yêu cầu tạo R2 secrets hoặc bật hai cờ R2. Mã tham khảo cũ được giữ, không có tài nguyên R2 được kích hoạt.

## Backup D1 về Windows

`scripts/free_d1_backup.py` tái sử dụng restore/integrity/FK/ledger/audit verification và GPG của pipeline hiện hành. Export database được chọn qua config Wrangler, kiểm trên SQLite tạm, đóng gói/check lại, mã hóa public key, ghi bằng chế độ không ghi đè, fsync và đọc lại SHA256 trước khi ghi sidecar hoàn tất. SQL/bundle giải mã chỉ ở thư mục tạm riêng và được dọn khi lệnh kết thúc bình thường. Không gọi AWS/R2 hoặc upload SQL lên GitHub. Nếu máy bị tắt đột ngột giữa export, file tạm có thể còn lại; không công khai hoặc sao chép chúng lên Git.

Thư mục hiện hành ngoài repository:

```text
%LOCALAPPDATA%/NgocThanhPOSDeployment/
  free-d1-backups/<database UUID>/*.tar.gz.gpg
  free-d1-backups/<database UUID>/*.tar.gz.gpg.sha256
  free-d1-backup-status.json
  free-d1-backup-restore-drill.json
```

Ngân sách mặc định 8 GB/database, không tự xóa backup cũ. Hết ngân sách hoặc lỗi export/mã hóa/checksum thì báo thất bại và giữ nguyên bản cũ. File ciphertext thiếu sidecar không phải backup hoàn tất. Lock có sẵn sẽ chặn chạy chồng; nếu máy tắt đột ngột, kiểm chắc không có lượt backup đang chạy trước khi xử lý lock cũ. Không tự xóa lock để bỏ qua một lượt đang chạy.

## Lịch trên máy này

Task `NgocThanhPOS-Free-D1-Backup-Staging`: 02:30 hằng ngày và khi tài khoản Windows hiện hành đăng nhập; có StartWhenAvailable, chạy quyền Limited/Interactive, không lưu mật khẩu Windows và không chạy chồng. Chỉ dành cho staging đã được phép. Máy phải bật, có mạng, người dùng đã đăng nhập và phiên Cloudflare Wrangler còn làm mới được. Không hứa vẫn backup khi máy tắt hoặc người dùng đã đăng xuất. Nếu đăng nhập Cloudflare hết hiệu lực, đăng nhập lại trên chính máy này; không đưa OAuth token lên GitHub.

Lịch phụ thuộc đường dẫn repository, Node/GPG và Python đang cài trên máy. Máy này dùng Python embeddable 3.14.10 từ python.org trong `%LOCALAPPDATA%/NgocThanhPOSDeployment/python-3.14.10`, độc lập với runtime Codex; SHA256 ZIP `90905e64a840557d8c1bc4f5b74db3d7ee85e3ffb217611cac1c7813acea4159` đối chiếu [trang phát hành](https://www.python.org/downloads/release/python-31410/) và chữ ký python.exe Valid. Với embeddable, `python314._pth` có thêm đường dẫn tuyệt đối thư mục scripts của repository; Python cài thông thường không cần bước này. Không sửa PATH toàn máy hoặc cài subscription.

Khi đổi thư mục dự án hoặc cập nhật/gỡ runtime Python, cần kiểm tra lại action của task và đường dẫn trong `_pth`, không xem task tồn tại là backup còn hoạt động. Không đổi binding production để chạy thử.

```powershell
./scripts/free-backup-windows.ps1 -Mode Status
./scripts/free-backup-windows.ps1 -Mode Run -PythonExecutable 'DUONG_DAN_PYTHON_3.12_TRO_LEN'
./scripts/free-backup-windows.ps1 -Mode Verify -PythonExecutable 'DUONG_DAN_PYTHON_3.12_TRO_LEN'
./scripts/free-backup-windows.ps1 -Mode Install -PythonExecutable 'DUONG_DAN_PYTHON_3.12_TRO_LEN'
```

Status phải có lượt mới `success`, checksum hợp lệ, thời gian đủ gần và LastTaskResult=0 sau khi task đã kết thúc. Task đang chạy có result khác 0 tạm thời; không công nhận trước khi kết thúc. `Verify` nhập private export vào keyring tạm mới, lấy passphrase từ DPAPI trên máy này qua môi trường của process, giải mã và restore/check bundle; không đưa passphrase vào argv/log. Cài lịch mới bằng `-Mode Install` chỉ sau Run và Verify đúng ciphertext thành công. Với task đã có, chỉ cập nhật action nếu đúng tên, script, mô tả, quyền Limited và không đang chạy; không thay một task khác.

## Khôi phục và bản sao độc lập

[Khóa GPG do chủ giữ](owner-backup-key.md) vẫn cần thiết. Giữ private key/passphrase ngoài máy, tách khỏi nhau. Có thể chép ciphertext + sidecar ra USB hoặc máy khác đang có sẵn; chưa xác minh cửa hàng đã có bản sao độc lập này. Mất cả máy và khóa trên cùng máy sẽ không được bảo vệ bởi lịch backup này.

Trước khôi phục: so hash ciphertext với sidecar, giải mã vào nơi riêng bằng private key, chạy `cloud_backup.py verify-bundle`, sau đó theo [quy trình restore](cloud-restore.md) trên database mới cách ly và đối soát tất cả máy. Không trỏ app vào bản cũ rồi bán ngay. D1 export không chứa ảnh chỉ nằm cục bộ: vẫn giữ backup SQLite/media của từng máy.

## Giới hạn Free được đối chiếu 18/11/2026

Workers Free: 100.000 request/ngày và 10 ms CPU/request. D1 Free: 5 triệu rows read/ngày, 100.000 rows written/ngày, 5 GB tổng tài khoản và 500 MB/database. Các hằng số cấu hình nằm ở `api/src/config.ts`; không thay bằng cam kết không giới hạn. D1 Free trả lỗi khi hết hạn mức; không cần nâng gói để giữ dữ liệu chờ đồng bộ. Export vẫn có thể ảnh hưởng hạn mức/khóa D1 ngắn hạn; số đo billing riêng của export chưa được xác định.

Nguồn chính thức: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), [D1 limits](https://developers.cloudflare.com/d1/platform/limits/). Chính sách nhà cung cấp có thể đổi; không tự chuyển sang Paid.
