# Bản chạy thử 0.7.0+7 — schema 30

So với 0.6/schema 29: hoàn thiện kho audit cũ với gzip/R2/checkpoint/receipt/guard, tiếp tục chain và replay sau archive; giao diện quản lý kho log; công cụ restore D1 dùng bind parameters cho dữ liệu lớn; mẫu cấu hình Worker assets + API cùng origin và cấu hình ký Android từ môi trường.

204 test Flutter toàn bộ/analyze sạch, 169 test API/typecheck/lint/dry-run và 19 test Python backup/restore đạt. Diễn tập process kill trước/sau commit trên schema 30 đã đạt trọn lượt: integrity, counter 001/002, replay, tồn, audit và outbox. Windows/Web/APK 0.7 build cuối đạt; Windows ZIP 66 file manifest/hash/EXE/migration và Web ZIP 75 file manifest đã xác minh. APK versionCode 7, schema 30, v2, Internet và ba ABI đạt. Checksum cả ba gói đã kiểm. APK cần Android 7.0/API 24 trở lên. APK ký debug do chưa có khóa chủ. Guard cấu hình ký thiếu đã đạt test Gradle offline.

HTTP workerd/D1/R2 local đạt archive trọn luồng và khôi phục SQL sau archive. Importer đã chạy trên D1 workerd local, có TEXT >100KB, BLOB 200KB, int64 >2^53, FK/self-reference, sequence 9999 và checksum mọi bảng; remote quick_check/FK đạt. Chrome release đã chạy các trang quản lý/audit/archive desktop-mobile và thu hồi phiên trên route private; không lỗi JS. Combined Worker assets local phục vụ HTML/JS và giữ API JSON401/no-store đúng.

Các mốc này không phải nghiệm thu cloud production hoặc thiết bị thực. Chưa push/deploy, chưa bật Actions/paid services, chưa ký APK bằng khóa chủ. Đọc ../operations/release-and-cloud-setup.md trước dùng; không dùng dữ liệu thật cho preview. Snapshot native/backup và bucket archive phải được giữ khi nâng cấp/restore. Không xóa hàng đợi để làm số khớp.

Tất cả nhóm nghiệp vụ đã có trong source: POS/kho/size/barcode/PDF/mã chứng từ; combo/trường/lớp/học sinh/giá-khuyến mãi; may riêng/đổi trả/cọc-công nợ/giữ hàng; nhân viên/quyền/chấm công/lương; chuyển kho; báo cáo và đồng bộ/sao lưu/audit đa cửa hàng. Web là chế độ quản lý/report online, không phải bản POS offline; chốt/cấu hình/in lương thực hiện native sau đối soát.

Đề xuất: không có tính năng ngoài phạm vi.

Bổ sung bộ cài Windows per-user và CRT app-local: đã kiểm thử lifecycle cài/sửa/nâng/hạ/chặn khóa/gỡ giữ dữ liệu fixture. ZIP có 66 tệp manifest. Xem windows-installer.md; chưa ký Authenticode hoặc nghiệm thu Windows sạch.
