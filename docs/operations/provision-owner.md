# Khởi tạo chủ cloud có kiểm soát

Công cụ dành cho D1 mới, đã migrate đủ schema hiện hành và chưa có dữ liệu. Không có public route mới và không bật ENVIRONMENT=development trên Worker cloud.

Trong api, đặt PROVISION_OWNER_PASSWORD bằng môi trường riêng (16–200 ký tự, mật khẩu mạnh; không đưa vào argv, source hoặc chat). Cấu hình local là JSON hợp lệ, ENVIRONMENT=production, account_id và D1 binding DB đúng database. Dùng CLI:

```powershell
node scripts/provision-owner.mjs --config wrangler.staging.local.jsonc
node scripts/provision-owner.mjs --config wrangler.staging.local.jsonc --execute-cloud --confirm-empty-database UUID_DATABASE_MOI
```

Lệnh đầu chỉ preview metadata công khai, không đọc token hoặc gọi cloud. Lệnh ghi bắt buộc cả cờ thực thi lẫn UUID trùng cấu hình. Token lấy từ CLOUDFLARE_API_TOKEN hoặc phiên OAuth Wrangler trong RAM, không ghi ra file/log/argv. Không retry write khi mất phản hồi: kiểm tra database trước khi chạy lại, không tự xóa marker hoặc đổi mật khẩu owner đã có.

KDF PBKDF2-SHA256/600000 chạy trên Node ở máy quản trị; D1 chỉ nhận salt và verifier lớp ngoài tương thích client. Không băm nặng trong Worker. Kết quả chỉ in receipt chứa ID/username, không chứa mật khẩu, credential hoặc token. Không in HTTP error body có khả năng chứa SQL/bind.

Trước khi ghi, công cụ kiểm tra đủ phiên bản migration liên tục và các bảng nghiệp vụ trống. Marker duy nhất/NOT NULL kiểm lại điều kiện trống trong cùng batch với store, Web device approved, owner/assignment và audit. Dữ liệu đến sau preflight hoặc lỗi ở cuối batch hủy toàn bộ việc khởi tạo. Không dùng để nhận quản trị database đã có dữ liệu.

Owner đầu tiên có trình duyệt Web W1; chưa gắn installation_hash cho đến đăng nhập thành công. Dùng đúng ID được receipt trả về. Không dùng terminal kiểm thử để claim trình duyệt bàn giao: kiểm thử staging đã dùng QA riêng và thu hồi sau đó. Công cụ chưa thêm dữ liệu mẫu, nhân viên khác hoặc hàng hóa; thiết bị bán hàng tiếp theo đi qua luồng invite/enroll/approve của API hiện có.

Trong staging ngày 17/11, mật khẩu ngẫu nhiên được lưu bằng Windows DPAPI ngoài repository. Xem staging-access.md để chủ tự xem mật khẩu và cấu hình đầu tiên. Có thể đổi mật khẩu bằng UI hiện có; sau khi đổi, credential XML cũ không tự cập nhật và không được coi là mật khẩu hiện hành.

Kiểm chứng: 5 test business guard/rollback/race/schema và 2 test CLI preview/confirm/secrets đạt; toàn bộ API 176 test đạt, typecheck/lint đạt. CLI đã thực thi trên D1 mới và 14 kiểm tra HTTP thực đã xác nhận đăng nhập/quyền/health. DB có dữ liệu hoặc marker từ lần thành công sẽ bị từ chối, không reset.
