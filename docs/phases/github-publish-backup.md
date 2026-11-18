# Xuất bản mã nguồn và workflow backup — 18/11/2026

LEVEL 3 cho cấu hình sao lưu, quyền xuất bản và bảo vệ dữ liệu. Người dùng đã cho phép riêng push mã nguồn/workflow lên GitHub và cấu hình R2 nếu không phải bật thanh toán. Không thay production hoặc bật subscription.

## Kiểm chứng trước khi xuất bản

- Flutter analyze sạch; 209 test Flutter toàn bộ đạt trong 02:20.
- API typecheck/lint sạch, 178 test đạt; Workers build dry-run đạt, không deploy.
- 23 test Python backup/restore/key guard đạt, gồm mã hóa GPG thật; 3 test workflow gate mới đạt (thiếu cờ, đủ hai cờ, chặn chèn output qua giá trị cờ).
- Rà soát 457 tệp văn bản thuộc danh sách Git: không phát hiện các mẫu private key/OpenPGP private key/GitHub token/AWS access key đã kiểm tra. Đây không phải cam kết phát hiện mọi loại secret. Private exports, credentials, database, APK/EXE/ZIP và cấu hình cloud local đều không được stage.
- Remote main và local cùng commit gốc trước khi xuất bản; không force push hoặc ghi đè thay đổi của người khác.

## Sửa điều kiện workflow

Đưa kiểm tra hai cờ từ job-level vào bước gate, sau khi GitHub nhận Environment private-backup. Các bước cài công cụ/export/upload/status artifact chỉ chạy khi cả hai chuỗi bằng true. Khi tắt, summary nói rõ không tạo hoặc xác nhận bản backup mới; không dùng trạng thái job xanh thay cho chứng cứ backup.

Cơ sở: [GitHub environment variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables). Không thay cơ chế mã hóa, integrity, upload/readback/hash hay retention.

## R2 vẫn bị chặn

Kiểm tra Wrangler được xác thực nhưng R2 vẫn activation-required/10042. [Hướng dẫn chính thức](https://developers.cloudflare.com/r2/get-started/) yêu cầu hoàn tất checkout để thêm R2 subscription. Không thực hiện checkout theo phạm vi cho phép. Chưa có bucket/secrets R2, chưa bật hai cờ lịch, chưa có backup cloud hằng đêm được nghiệm thu.

Tình trạng commit/push và CI GitHub được ghi sau khi có phản hồi thực từ remote. Kết quả test trên đây là chạy local, không suy thành GitHub CI đã đạt.

Đề xuất: không thêm tính năng.