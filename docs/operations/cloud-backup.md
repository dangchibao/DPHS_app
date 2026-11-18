# Sao lưu cloud và diễn tập khôi phục

Pipeline đã chuẩn bị trong `.github/workflows/cloud-backup.yml` và `scripts/cloud_backup.py`. Chưa kích hoạt, chưa chạy trên tài khoản Cloudflare/GitHub thật. Không tự tạo bucket, bật thanh toán, deploy hay thay database production.

## Luồng và lịch

GitHub Actions chạy dự kiến 02:30 Việt Nam, có thể bị GitHub trì hoãn. Wrangler xuất D1 bằng token môi trường; script khôi phục SQL vào SQLite tạm, kiểm `integrity_check`, khóa ngoại và tồn cache so với sổ cái. Sau đó tạo tar/gzip chứa SQL và manifest SHA256/số dòng/schema; kiểm lại gói; mã hóa GPG bằng khóa công khai. Khóa giải mã không nằm trên Actions. Chỉ ciphertext và checksum ciphertext được đưa vào bucket R2 riêng.

Sau upload, HEAD kiểm kích thước và tải lại ciphertext để đối chiếu SHA256. Chỉ sau bước này mới xoay vòng: hợp của 30 ngày, 4 tuần, 12 tháng gần nhất, chọn một bản mới nhất mỗi kỳ theo giờ Việt Nam. Không xóa object khác prefix/database, tên sai định dạng hoặc upload thiếu sidecar. Bản mới thất bại không đẩy bản cũ khỏi retention. Script kiểm ngân sách bucket trước upload, mặc định 8.000.000.000 byte; vượt thì dừng, không tự nâng gói hoặc xóa bản tốt để nhường chỗ.

Chạy lỗi trả exit khác 0, job GitHub thất bại, có Job Summary và artifact trạng thái 7 ngày nếu bước script đã chạy. Không upload SQL, file giải mã, khóa hoặc manifest dữ liệu lên artifact. Chủ cần bật thông báo thất bại workflow trong GitHub; kiểm tra lần chạy gần nhất hằng ngày vì lịch có thể bị tắt khi repository không hoạt động. Không có email/Slack được tự gửi bởi ứng dụng.

## Chuẩn bị bởi chủ khi được phép sử dụng cloud

1. Repository hiện hành là public. Chỉ xuất bản source/workflow; SQL, private key, credential và artifacts backup không được đưa vào Git hoặc artifact công khai. Cấp secrets trong Environment `private-backup`; kiểm tra ngân sách Actions. Dùng runner tiêu chuẩn, không bật runner lớn hoặc tự mua hạn mức. Lịch không đồng nghĩa dịch vụ luôn miễn phí.
2. Tạo bucket **chỉ dành cho backup**, tắt `r2.dev` và custom domain công khai. Không gắn bucket này vào Worker POS hoặc trình duyệt. R2 phải được chủ kiểm tra điều kiện đăng ký/thanh toán và cho phép riêng trước khi bật.
3. Tạo cặp khóa GPG tại máy quản trị an toàn, xuất public key dạng ASCII armor. Ghi fingerprint đầy đủ, giữ private key + mật khẩu ở hai nơi do chủ kiểm soát. Thử giải mã một bản trước khi tin vào lịch tự động. Pipeline từ chối nhận secret key hoặc public key khác fingerprint.
4. Token Cloudflare cho export cần **D1 Write** (export khóa database), giới hạn đúng account/database nếu chính sách Cloudflare hỗ trợ. Không dùng Global API Key. R2 access key chỉ Object Read/Write cho đúng bucket backup; không cấp tài khoản POS quyền đọc backup. Thu hồi/đổi khóa khi cần, không commit.
5. Tạo GitHub Environment `private-backup`, điền variables/secrets bên dưới. Hai cờ xác nhận được đọc ở bước gate sau khi job nhận Environment, không kiểm ở cấp job. Thiếu một cờ hoặc giá trị khác chuỗi `true` thì chỉ ghi summary “Backup chưa bật”, không export/upload; trạng thái job thành công khi tắt không phải một bản backup thành công. Không đặt người duyệt bắt buộc cho job lịch nếu muốn tự động; quyền bật workflow/config do chủ quản lý.
6. Đo một lần export/restore trên staging được chủ cấp phép, ngoài giờ. Ghi rows read/written/size từ D1 Analytics/meta trước/sau, thời gian khóa DB và dung lượng backup, không suy ra export là 0 reads. Sau diễn tập thành công mới đặt hai variables bật lịch thành `true`.

Variables: `CLOUDFLARE_ACCOUNT_ID`, `D1_DATABASE_ID`, `R2_BACKUP_BUCKET`, `R2_ENDPOINT_URL` (`https://<account>.r2.cloudflarestorage.com`), `BACKUP_GPG_FINGERPRINT`, `R2_BACKUP_STORAGE_BUDGET_BYTES`, `CLOUD_BACKUP_ENABLED`, `R2_PRIVATE_BACKUP_CONFIRMED`.

Secrets: `D1_BACKUP_API_TOKEN`, `R2_BACKUP_ACCESS_KEY_ID`, `R2_BACKUP_SECRET_ACCESS_KEY`, `BACKUP_GPG_PUBLIC_KEY`. Public key không bí mật nhưng dùng secret để tránh làm nhiễu log. **Không cung cấp private key.** Không có credential mặc định trong repository.

## Diễn tập local, không ghi cloud

Tại gốc dự án, Python 3.12+ có SQLite/JSON1, GnuPG trên PATH:

```powershell
python -m unittest discover -s scripts -p test_cloud_backup.py -v
python scripts/cloud_backup.py drill-sql artifacts/database-thu.sql
python scripts/cloud_backup.py verify-bundle artifacts/database.tar.gz
```

Nếu thiếu GnuPG, bài mã hóa thật được đánh dấu skip; không được báo đã kiểm chứng mã hóa. Các bài còn lại vẫn chạy. Mỗi lần chạy pipeline cũng tự thực hiện restore SQL/gói vào file tạm. Diễn tập giải mã bằng private key thực hiện tại máy quản trị; không đưa private key lên Actions chỉ để kiểm thử:

```powershell
gpg --output artifacts/database.tar.gz --decrypt artifacts/database.tar.gz.gpg
python scripts/cloud_backup.py verify-bundle artifacts/database.tar.gz
```

Trước giải mã, đối chiếu SHA256 ciphertext với sidecar từ nguồn tin cậy. `verify-bundle` từ chối đường dẫn traversal/link, checksum/schema/số dòng sai, SQL ATTACH/extension hoặc số dư kho lệch sổ cái. Chỉ tạo file tạm mới; không mở file SQLite đang bán để restore. Không commit SQL, dữ liệu giải mã, file khóa hay database thử. Đảm bảo dung lượng ổ trống đủ cho SQL + SQLite + archive.

## Khôi phục cloud có kiểm soát

1. Chủ thông báo tạm ngừng ghi cloud và cho phép thao tác khôi phục riêng. Native vẫn có thể có giao dịch offline; giữ nguyên outbox và snapshot từng máy. Đừng thu hồi/xóa queue để làm số khớp.
2. Lưu backup/export hiện trạng và bookmark Time Travel nếu còn khả dụng. Tải ciphertext đã xác minh, giải mã ở máy quản trị, chạy `verify-bundle`; đối chiếu kỳ dữ liệu, schema và các chứng từ mẫu.
3. Ưu tiên thử trên **database D1 mới, trống**, dùng binding staging riêng. Không chạy file export trực tiếp vào database đang có dữ liệu. Export D1 có thể có statement dài hơn giới hạn SQL import; kiểm tra độ dài statement. Với dữ liệu JSON lớn phải dùng công cụ import có bind parameters/kiểm soát lô, không cắt SQL bằng xuống dòng hoặc dấu `;` trong chuỗi. Đã có scripts/cloud_restore.py dùng bind parameters, kiểm schema/FK/checksum và chỉ nhập staging mới. Xem cloud-restore.md; mặc định diễn tập local, cần phép riêng và cờ xác nhận đúng UUID mới để ghi cloud.
4. Trên staging kiểm số dòng, khóa ngoại, sổ kho/cache, snapshot HD/MR/DT, payments/công nợ, audit hash chain, processed mutation IDs, private payroll và cursor `server_seq`. Không reset processed mutations hoặc bộ đếm tùy ý.
5. Restore bản cũ làm server có thể mất ACK/giao dịch mà máy khác đã nhận. **Không chỉ trỏ app sang DB cũ rồi bán tiếp.** Cần đối soát tất cả máy, giữ danh tính/mã chứng từ, gửi lại idempotent các chứng từ mất trên server. Thiết bị chưa liên hệ được là một rủi ro chưa giải quyết; giữ chặn bán/đối soát phù hợp. Chỉ chủ cho đổi binding production sau kiểm thử.
6. Sau khi nối lại, theo dõi debt/ledger/cursor và một ngày doanh thu, ghi biên bản restore/audit. Giữ nguyên database cũ và backup trước restore cho đến khi chủ quyết định retention.

Time Travel là lớp phụ; Free hiện giữ 7 ngày, không thay backup mã hóa ngoài database. Không chạy restore production từ workflow lịch.

## Hạn mức và chi phí

Export có thể khóa database; Worker/POS phải giữ queue và retry khi cloud bận. D1 export cần đo tác động thực tế; chưa cam kết không tiêu tốn reads. R2 Free dùng chung account, ngân sách bucket trong script không đo được các bucket khác. Upload có thêm GET kiểm checksum, LIST và các DELETE khi xoay vòng; không chọn Infrequent Access. Chủ cần theo dõi cả R2 operation/storage và ngân sách Actions, không bật tính phí ngoài hạn mức khi chưa duyệt riêng.

Nguồn chính thức kiểm tra 17/11/2026: [D1 import/export](https://developers.cloudflare.com/d1/best-practices/import-export-data/), [quyền export](https://developers.cloudflare.com/d1/observability/debug-d1/), [D1 limits](https://developers.cloudflare.com/d1/platform/limits/), [R2 S3 API](https://developers.cloudflare.com/r2/api/s3/api/), [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Khi chạy script thủ công, dùng R2_BUCKET (workflow ánh xạ từ variable R2_BACKUP_BUCKET); AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY được workflow ánh xạ từ secrets R2_BACKUP_ACCESS_KEY_ID/R2_BACKUP_SECRET_ACCESS_KEY. Không đặt giá trị thật vào tài liệu hoặc lệnh được ghi log.

Cập nhật 18/11: [khóa GPG do chủ giữ](owner-backup-key.md) đã tạo và diễn tập nhập private export vào keyring mới→giải mã/verify_bundle/restore đạt với D1 QA thật. Đây chưa phải lịch R2 đã bật. Không upload private key lên Actions; chỉ dùng public key và fingerprint.
