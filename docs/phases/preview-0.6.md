# Bản chạy thử 0.6.0+6 — schema 29

17/11/2026. Bổ sung so với preview 0.5/schema 21: bảng lương/phiếu lương; báo cáo local, cloud và tổng cửa hàng; Web quản lý online; ảnh sản phẩm/nén/cache/R2 tùy chọn; QR ngân hàng; usage/free-tier; bàn giao quyền đa máy; ngưỡng cảnh báo đồng bộ; nhật ký cloud đa cửa hàng; pipeline backup cloud mã hóa và diễn tập ngắt tiến trình.

Windows portable: giải nén toàn bộ ZIP, mở ngoc_thanh_pos.exe cùng DLL/data. Android APK: ký debug, versionCode 6, dùng thử; không phải khóa ký phân phối do chủ quản lý. Các bản 0.5 và trước được giữ nguyên. Không mở đồng thời hai phiên Windows trên cùng database.

Tài khoản admin/mật khẩu lấy từ .env khi chạy script; bản cài mới có màn khởi tạo mật khẩu. Không chứa mật khẩu bootstrap trong gói. Dữ liệu mẫu chỉ dùng thử. Với cloud, máy mới phải được mời/duyệt và trỏ API hỗ trợ schema 29. Không kết nối production sẵn.

Kiểm chứng: 201 test Flutter toàn bộ đạt/analyze sạch; API 163 test nghiệp vụ đạt/typecheck/lint/Worker dry-run. 10 test backup Python đạt; diễn tập process kill SQLite thật trước/sau commit đạt. Windows, Web release và APK đã build thành công. APK v2/Internet/ba ABI đã kiểm tra. Chrome Web release schema 29 đã kiểm chứng đăng ký/duyệt/đăng nhập KDF, dashboard, catalog, roster lương, nhật ký desktop/mobile và thu hồi phiên, không có lỗi JavaScript. Manifest/checksum gói được xác minh riêng sau đóng ZIP.

Xem store-settings-web-management.md, staff-handoff.md, media-bank-usage.md, reports-cloud-web.md và cloud-backup.md để biết phạm vi/giới hạn. Chưa nghiệm thu trên máy quét, máy in, Android/iOS hoặc nhiều máy native vật lý. Chưa kích hoạt Cloudflare/GitHub Actions, đo billing/CPU thật hoặc dùng khóa ký Android chính thức.

Phần vẫn đang phát triển: kho lưu trữ/purge nhật ký cũ có checkpoint và khôi phục cloud cho dump chứa statement lớn. Backup toàn D1 không thay thế kho archive. Không tuyên bố hoàn thành toàn bộ yêu cầu.

Đề xuất: không bổ sung ngoài phạm vi.
