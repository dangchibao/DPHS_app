# Kiểm chứng hai máy offline và mất ACK — 17/11/2026

LEVEL 3: khả năng phục hồi và chống trùng giao dịch. Bổ sung kiểm thử vào app/test/two_device_recovery_test.dart; không đổi logic ứng dụng hoặc schema 30.

Hai file SQLite riêng, mỗi file dùng executor riêng, cùng danh mục và sổ cái ban đầu: máy A được phân bổ 10, máy B được phân bổ 4, tổng tồn 14. Hai LocalService thực bán offline độc lập: A bán 3 và B bán 4. Mã HD cùng ngày có mã máy khác nhau, đều số 001. Máy B bị chặn bán thêm dù cache còn thấy hàng của A; không phát sinh chứng từ/hàng đợi của lần bán bị chặn.

SyncEngine/CloudApi thực dùng HTTP protocol fixture để ghi nhận mutation nguyên văn và trả lại các bản ghi do client tạo. Fixture mô phỏng nhận mutation của A rồi làm mất phản hồi ACK. Hàng đợi A phải giữ nguyên. Đóng/mở lại file A, gọi lại lệnh bán cùng command ID, sau đó dùng engine mới gửi lại. Fixture kiểm UUID và nội dung mutation không đổi giữa các lần gửi. Không cài lại logic giá, kho hoặc công nợ trong fixture.

Kéo lại các sự kiện tài chính của cả hai máy và cố ý phát lại feed đã thấy: mỗi file cuối cùng có đúng 2 hóa đơn, 2 thanh toán, tổng thu 700.000 VND; 4 bút toán kho, tổng ledger và cache đều 7; outbox hết, bộ đếm riêng vẫn 001. integrity_check và foreign_key_check đạt trên cả hai file. Tệp tạm do test tự tạo được đóng và dọn; không mở SQLite người dùng.

Kiểm chứng: test mới chạy độc lập đạt; flutter analyze sạch. Lượt toàn bộ cuối đạt 205 test Flutter (02:26, exit 0), gồm cả regression hai file SQLite và ca thu hồi lease có timeout điều chỉnh. API/Python không thay đổi và không chạy lại trong lượt này.

Lượt toàn bộ đầu gặp timeout 30 giây ở ca local_auth_revocation_test.dart dùng nhiều lần KDF thật. Chạy riêng ca này đạt trong khoảng 31 giây. Đã đặt timeout 2 phút cho riêng ca đó (phù hợp nhóm auth hiện có), không đổi assertions, thuật toán băm, quyền hoặc mã sản phẩm. Lượt đầu được giữ ở artifacts/flutter-two-device-first-test.log; lượt chạy lại ở artifacts/flutter-two-device-final-test.log.

Chạy tại app: `flutter test test/two_device_recovery_test.dart`. Kiểm thử tự được chạy trong CI Flutter hiện có, không cần cấu hình dịch vụ hoặc thêm secrets.

Giới hạn: đây là kiểm thử client/SQLite với protocol fixture, không phải nghiệm thu hai điện thoại/PC thật hoặc gọi API Cloudflare production. Tính idempotent và quyền của API có bộ kiểm thử riêng đã ghi ở các phase trước; fixture không thay thế bằng chứng đó. Không build lại EXE/APK/Web vì mã sản phẩm không thay đổi; gói 0.7.0 vẫn là bản chạy thử đã phát hành trước lượt kiểm chứng này.

Đã cập nhật đầu progress.md để phân biệt trạng thái hiện tại với các giới hạn trong lịch sử schema cũ, tránh coi những module đã hoàn thiện là backlog.

Đề xuất: không có tính năng ngoài yêu cầu.
