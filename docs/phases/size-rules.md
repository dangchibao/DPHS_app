# Bảng quy đổi và gợi ý size — LEVEL 2, schema 19

Đã có bảng size theo cửa hàng, dùng chung hoặc gắn sản phẩm. Chủ/quản lý có quyền catalog thêm/sửa/ngừng áp dụng; thu ngân/kho đọc để gợi ý. Mỗi bảng 1–50 size, tên không trùng, cấu hình khoảng chiều cao/cân nặng. Không có số đo tiêu chuẩn hard-code trong thuật toán hoặc tự chọn khi ngoài bảng.

Giao diện nhập cm/kg; dùng lại bộ chuyển đổi số nguyên của may riêng để lưu mm/gram. Hai cận được tính bao gồm; phải khớp cả chiều cao lẫn cân nặng. Vùng giao nhau trả mọi size theo thứ tự cấu hình, không tự đoán ưu tiên. Hiển thị bảng quy đổi, cấu hình sản phẩm, trạng thái và gợi ý trên mobile.

Lưu cấu hình, audit và outbox cùng transaction. API kiểm quyền/schema/số nguyên/phiên bản/scope/sản phẩm; LWW cho cấu hình, không ảnh hưởng giá hoặc sổ cái kho. Có index bắt đầu store_id, guard không chuyển bản ghi giữa cửa hàng, migration Drift/D1 giống nhau. size_rules không tham gia tính tiền và không lưu số đo người đang thử vào audit.

Kiểm chứng: 9 ca Flutter mới đạt (5 vector dùng chung TS/Dart, dữ liệu sai, quyền/outbox, UI nhập bảng bằng cm/kg, UI gợi ý mobile). Toàn bộ 103 test API, typecheck/lint và migration D1 local 19 đạt. Các kiểm tra tích hợp bổ sung ghi tại progress.md. Gói Windows/APK 0.4.0 đã phát trước đó ở schema 18, chưa gồm phần size mới; dùng source để thử.

Chạy `./scripts/dev.ps1` → **Bảng quy đổi · gợi ý size**. Quản lý chọn **Thêm bảng size**, nhập tên/sản phẩm và các dòng size với khoảng cao/nặng; lưu. Nhập chiều cao/cân nặng rồi chọn **Gợi ý size**. Bảng cấu hình ban đầu để trống để cửa hàng nhập thông số đúng sản phẩm thực tế.

Chưa có chuyển kho, lương/báo cáo/Web quản lý hoàn chỉnh hoặc ảnh/QR/R2. Chưa nghiệm thu với bộ size thực tế của cửa hàng. Đề xuất: không thêm ngoài phạm vi.
