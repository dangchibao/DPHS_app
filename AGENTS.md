# Quy tắc dự án Đồng phục Ngọc Thanh

- Stack cố định: Flutter/Dart, Riverpod, Drift/SQLite, Workers TypeScript, D1. Không Firebase.
- Giao diện tiếng Việt; tiền nguyên VND. Windows/Android offline-first; Web/PWA quản lý online, không POS offline.
- Phân loại LEVEL 1/2/3 trước nhiệm vụ. Chỉ đọc file liên quan; kiểm thử phù hợp, không sửa module ngoài phạm vi.
- Người dùng đã duyệt toàn bộ kế hoạch ngày 15/11/2026 và cho phép tiếp tục các phase không cần hỏi lại. Báo cáo sau phase, cập nhật tài liệu; chỉ yêu cầu người dùng khi thật sự cần thông tin/thao tác ngoài môi trường.
- Không push GitHub, triển khai cloud, thay đổi production hoặc kích hoạt dịch vụ trả phí khi chưa được phép riêng.
- Ngày 17/11/2026, sau khi đăng nhập Cloudflare, người dùng yêu cầu tiếp tục phần còn lại không hỏi duyệt: đã cho tiến hành staging riêng và ký APK trên máy này. Tiếp tục kiểm chứng/cấu hình staging trong phạm vi đó; không suy ra quyền thay production đã có, push GitHub hoặc bật subscription/thanh toán.
- Ngày 18/11/2026, người dùng trả lời “cho phép” cho việc push mã nguồn/workflow backup lên GitHub và cấu hình R2 nếu không cần bật thanh toán. Quyền này không cho bật subscription, thêm phương thức thanh toán hoặc thay production. Chỉ bật lịch backup sau upload/readback/restore đạt.
- Không tự xóa dữ liệu thật. Không secret hoặc mật khẩu hard-code. Tài khoản bootstrap admin lấy mật khẩu từ môi trường.
- Mọi tồn kho qua stock_movements; số dư là cache. Mỗi nghiệp vụ ghi dữ liệu, audit và outbox cùng transaction.
- Chứng từ đã phát hành và audit append-only. Tiền, giá vốn, sản phẩm lưu snapshot. Sửa sai qua chứng từ/sự kiện mới.
- RBAC kiểm tra ở API và local service. Phân tách dữ liệu cửa hàng; quyền và danh tính không tin từ payload client.
- UUID client; mã chứng từ có chi nhánh + thiết bị; bộ đếm cùng transaction. Sync idempotent, cursor, batch, backoff/jitter.
- Không cam kết không âm kho liên thiết bị offline nếu thiếu phân bổ quyền bán. Không dùng LWW cho quyền hoặc sổ cái kho.
- Sao lưu SQLite an toàn; kiểm tra integrity/checksum; restore có backup trước và chặn bán đến khi reconcile.
- Thay đổi phải có kiểm chứng thực tế. Không báo test/build/phase hoàn thành nếu chưa chạy thành công.
- Không tự thêm tính năng. Ghi Đề xuất trong báo cáo nếu có.
- README.md là hướng dẫn hiện hành; docs/phases ghi kết quả và giới hạn từng phase.
