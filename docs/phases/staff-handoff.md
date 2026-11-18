# Bàn giao quyền nhân viên — schema 28, 17/11/2026

LEVEL 3. Đổi vai trò/khóa nhân viên dùng yêu cầu bàn giao trước khi thu hồi quyền. Directory khóa tương tác mới; grant đồng bộ cũ tiếp tục gửi giao dịch đã có. Hoàn tất cần từng máy native liên quan gửi hết hàng đợi, kéo đến cursor hiện tại và xác nhận. Web không xác nhận thay máy native. Khóa toàn tài khoản phải chờ các cửa hàng liên quan.

Guard kiểm tra lại quyền hiện tại lẫn quyền lúc cấp phiên, snapshot hồ sơ, trạng thái yêu cầu và ACK trong cùng transaction với thay phân công, thu hồi phiên và audit. Sửa tên không thu hồi phiên; đổi vai trò một cửa hàng không thu hồi phiên cửa hàng khác. Hủy yêu cầu không hồi sinh lease offline. Máy mới được duyệt trong lúc bàn giao cũng phải xác nhận.

Giao diện Nhân viên → Bàn giao quyền dùng chung native/Web, hiển thị máy chờ, hoàn tất và hủy có lý do. Ảnh tùy chọn vẫn giữ cache/hàng đợi riêng; quản lý có quyền có thể gửi lại đúng ảnh để hoàn tất các intent trùng hash, không bỏ giao dịch tài chính.

Kiểm chứng schema 28:

- API: 155 test đạt, TypeScript và Prettier đạt.
- Flutter: analyze sạch, toàn bộ 195 test đạt, gồm 3 test bàn giao và test tiếp nhận lại ảnh.
- Backup: 10 test Python đạt, có GPG thật và kiểm tra khôi phục.
- Worker HTTP + D1/R2 local: tạo nhân viên, đóng băng tương tác/đăng nhập mới, gửi hóa đơn cũ bằng sync grant, chặn hoàn tất sớm, đợi hai ACK ràng buộc thiết bị, hoàn tất, thu hồi grant cũ và đăng nhập vai trò mới đều đạt. Các luồng CK, lương, báo cáo, ảnh và QR cũng đạt cùng fixture. Không gọi cloud thật.

Giới hạn: máy mất hoặc sync grant hết hạn không được tự coi là sạch. Cần lấy dữ liệu/đối soát; có thể hủy bàn giao, xác thực lại và gửi hết queue rồi chuẩn bị lại. Thu hồi thiết bị không tự giải phóng quyền bán. Xem thiết kế tại ../architecture/staff-handoff-design.md. Chưa kiểm chứng luồng nhiều máy vật lý.

Đề xuất: không có tính năng ngoài phạm vi.

Bổ sung kiểm thử bảo mật bản 0.7: khi đăng nhập nhận STAFF_HANDOFF_PENDING, máy thu hồi ngay lease offline đã lưu và hết hạn phiên tương ứng, giữ nguyên hàng đợi/sync grant. Ngắt mạng sau phản hồi này không mở lại quyền cũ; phải xác thực online lại sau khi hoàn tất/hủy bàn giao. Kiểm thử hồi quy đã đạt trong bộ 204 test Flutter.
