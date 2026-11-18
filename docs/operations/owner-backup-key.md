# Khóa mã hóa backup do chủ giữ — 18/11/2026

Đã tạo khóa GPG RSA 3072 chỉ dùng cho mã hóa, tên Ngoc Thanh POS Backup, thời hạn mã hóa 2 năm. Fingerprint đầy đủ:

`9CF7EAFBD6486A0B693BECE0F9FD92B791527F68`

Các tệp nằm ngoài repository, trong `%LOCALAPPDATA%/NgocThanhPOSDeployment`:

| Tệp/thư mục | Mục đích |
| --- | --- |
| cloud-backup-public.asc | Khóa công khai dùng cho pipeline |
| cloud-backup-private.asc | Private key export có passphrase, chỉ chủ giữ |
| cloud-backup-gpg | Keyring riêng, không thay keyring mặc định |
| backup-gpg-passphrase.credential.xml | Passphrase ngẫu nhiên được Windows DPAPI bảo vệ |
| cloud-backup-key-info.json | Fingerprint và kết quả lượt chuẩn bị/diễn tập gần nhất |
| cloud-backup-drill-*.tar.gz.gpg | Ciphertext diễn tập, không phải lịch backup đã bật |

**Sao lưu private key và passphrase độc lập ngoài máy trước khi dựa vào cơ chế này.** Chỉ chép XML DPAPI sang máy khác không bảo đảm giải mã được. Chủ tự xem passphrase trên máy/tài khoản Windows này khi lưu vào nơi an toàn; không gửi kết quả qua chat:

```powershell
$key = Import-Clixml "$env:LOCALAPPDATA\NgocThanhPOSDeployment\backup-gpg-passphrase.credential.xml"
$key.GetNetworkCredential().Password
```

Không đưa private key, passphrase hoặc keyring lên GitHub, Actions hay R2. Pipeline chỉ cần **public key** và fingerprint: secret `BACKUP_GPG_PUBLIC_KEY` lấy nội dung cloud-backup-public.asc, variable `BACKUP_GPG_FINGERPRINT` lấy fingerprint trên. Không dùng cloud-backup-private.asc cho bất kỳ secret nào của workflow. Quản lý gia hạn khóa trước khi hết hạn; không tự xoay sang khóa khác để bỏ qua lỗi.

## Công cụ và diễn tập

`scripts/prepare_backup_key.py` dùng Python/GPG hiện có. Đặt passphrase qua biến môi trường riêng `NT_BACKUP_KEY_PASSPHRASE`; không đưa vào argv/source/log. Mặc định dùng keyring hiện có; tạo đầu tiên cần `--create-key`. Không ghi đè export đã có, không tự tạo khóa khác khi keyring mất/rỗng nhưng vẫn còn bản sao khóa: cần phục hồi private key gốc.

```powershell
python scripts/prepare_backup_key.py
python scripts/prepare_backup_key.py --drill-sql DUONG_DAN_SQL_QA_RIENG
```

Lệnh diễn tập dùng logic backup hiện hành để kiểm SQL, nén và mã hóa; nhập private export vào keyring tạm mới, giải mã, so SHA256 bundle rồi verify_bundle/integrity/FK/ledger. Ciphertext được giữ riêng; dữ liệu giải mã tạm được dọn. Không gọi API cloud, không tạo bucket hoặc bật workflow.

Lượt thực ngày 18/11 đạt với SQL xuất từ database E2E có giao dịch giả; hồ sơ artifacts/cloud-backup-owner-key-drill.json. Đây chưa phải upload R2 hoặc lịch backup. Lượt cuối `python -m unittest discover -s scripts -p "test_cloud_*.py" -v` đạt 23 test, gồm 4 test bảo vệ tạo/khôi phục khóa mới.

## Điều kiện để chạy hằng đêm

**Phương án hiện hành không cần R2:** [backup tự động về Windows](free-operation.md). Các điều kiện R2/GitHub bên dưới là lịch sử của phương án đã bỏ, không phải việc chủ phải làm. Khóa GPG vẫn được dùng cho bản sao mã hóa trên máy; lịch chỉ chạy khi máy bật, tài khoản Windows đăng nhập và có mạng/phiên Wrangler hợp lệ.

- R2 vẫn trả 10042/chưa kích hoạt. Chủ cần tự xem điều kiện kích hoạt/chi phí của Cloudflare; chưa tự bật subscription hoặc phương thức thanh toán.
- Cần bucket R2 Standard private và token/S3 credentials quyền tối thiểu, đặt vào secrets theo cloud-backup.md; không gửi qua chat.
- Repository dangchibao/DPHS_app là public. Ngày 18/11 người dùng đã cho phép riêng và source/workflow được push main tại commit 97666f7. Chưa cấu hình secrets R2 hoặc bật lịch; private key không được xuất bản. Xem ../phases/github-publish-backup.md.
- Khi đủ bucket/secrets/workflow, chạy thủ công và kiểm upload→download/hash→giải mã/restore trước khi bật hai variable xác nhận lịch. Không coi job bị skip là đã sao lưu.

Giữ passphrase tách khỏi private key khi lưu ngoài máy. Không công khai ciphertext hoặc SQL của cửa hàng. Mã hóa không thay bản sao độc lập và diễn tập khôi phục định kỳ.
