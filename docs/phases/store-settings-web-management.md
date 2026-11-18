# Ngưỡng cảnh báo, nhật ký đa cửa hàng và quản lý Web — schema 29

17/11/2026. LEVEL 3 cho đồng bộ ngưỡng/kiểm tra quyền; LEVEL 2 cho các màn quản lý.

Ngưỡng hết hàng theo cửa hàng/biến thể có lịch sử stock_threshold_rules append-only, UUID client, actor và phiên bản UTC đến mili giây. Trigger dựng lại cache store_variant_settings từ rule mới nhất, không sửa price_override. Catalog, rule mới, audit và outbox cùng transaction SQLite; chỉ gửi rule vừa tạo, không giả người tạo rule cũ. Nhận ngược thứ tự hội tụ; replay không nhân đôi. Ngưỡng cũ được giữ khi nâng cấp và được xuất bản khi người có quyền lưu lại biến thể.

Giá riêng cửa hàng đã có qua bảng giá commercial_rules loại price_list, phạm vi cửa hàng, chọn tất cả trường/khách hoặc nhóm cụ thể. POS chọn bảng giá và lưu snapshot giá thực bán; không tự cộng dồn khuyến mãi. Không thêm một bộ máy tính giá song song.

Nhật ký cloud: chủ chọn từng/toàn hệ thống, quản lý chỉ cửa hàng mình; kiểm cả current và issued role. Lọc ngày (tối đa 31 ngày/lần), nhân viên, thiết bị, thao tác, đối tượng và mức độ. Keyset(store,time,id), tối đa 201 log được xét/request, 50 kết quả và khoảng 500KB. Trang không có kết quả vẫn có cursor để tiếp tục; không quét toàn bảng cho bộ lọc hiếm. UI native/Web có xem chi tiết. Dữ liệu chưa lên cloud vẫn xem tại Nhật ký local. Chưa thay thế kho lưu trữ log cũ.

Web quản lý online:

- Catalog: tạo/sửa sản phẩm và biến thể, SKU/mã vạch/size/màu/đơn vị/giá/năm học, ngừng bán, ngưỡng cửa hàng. Endpoint chỉ nhận catalog/rule, cấm ledger/payments/quyền/audit giả. Audit server cùng transaction, retry giữ nguyên UUID/payload và chờ đúng ACK. Tên/thuộc tính sản phẩm dùng chung các chi nhánh.
- Đổi mật khẩu: kiểm xác nhận/độ dài trước gửi, dùng KDF hiện có, xóa các ô và phiên RAM sau thành công.
- Lương online: chủ/kế toán xem nhân viên, kỳ đã chốt/hủy/cần đối soát và dự tính từ dữ liệu cloud; ghi audit mỗi lần xem lịch sử/dự tính. Cấu hình, chốt/hủy và PDF lương tiếp tục tại Windows/Android, nơi có luồng đối soát các máy. Trình duyệt không có quyền bán/quota/sync grant.

Kiểm chứng đã chạy:

- API toàn bộ 163 test đạt, typecheck/lint đạt; gồm ngưỡng hội tụ/rollback, audit phân quyền/keyset/index và Web catalog/lương.
- Flutter toàn bộ 198 test đạt tại mốc ngưỡng/audit; các test thêm cho mật khẩu, catalog mobile retry và lương mobile đều đạt. Analyze sạch. Lượt tích hợp cuối: 201 test Flutter toàn bộ đạt; Windows/Web/APK release schema 29 build đạt. Chrome release đã chạy thật enrollment/login/dashboard/catalog/roster lương/audit desktop và mobile/revoke, không lỗi JS; screenshot đã kiểm tra trực quan.
- Worker HTTP D1/R2 local: schema 29 migration đạt; ngưỡng push/replay/feed và chủ đọc audit mọi cửa hàng đạt. Browser enrollment/login không sync grant, lưu catalog+ngưỡng/replay/đọc lại giá, xem lương có phiếu hủy và chặn ghi kho đều đạt.
- Ngắt tiến trình Flutter thật tại SQLite WAL/FULL: trước commit không có hóa đơn/counter/audit/outbox bán, tồn giữ nguyên; sau commit còn một hóa đơn, retry cùng command không trùng; hóa đơn tiếp theo số 002. Integrity/FK/ledger/cache/audit/outbox đạt, script kết thúc thành công. Đây là process kill, không phải thử rút nguồn phần cứng.

Chạy: ./scripts/dev.ps1; Web ./scripts/dev.ps1 -Target chrome (API/schema 29). Diễn tập độc lập: python scripts/crash_recovery_test.py. Dùng database tạm, không mở dữ liệu bán thật. CI thêm diễn tập này sau Flutter test.

Giới hạn: chưa chạy trên máy in/máy quét/Android/iOS vật lý; chưa triển khai cloud hoặc đo quota thật. Chưa lưu trữ/purge log cũ khỏi D1; pipeline sao lưu toàn D1 không thay thế yêu cầu này. Bản phát hành preview trước vẫn được giữ nguyên.

Đề xuất: không có tính năng ngoài phạm vi.
