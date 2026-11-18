# Bàn giao quyền nhân viên — LEVEL 3, thiết kế triển khai

Không đổi quyền/khóa ngay rồi làm mất khả năng gửi giao dịch cũ. Cloud giữ phân công cũ trong thời gian chuẩn bị; chỉ chặn tương tác mới của nhân viên bị đóng băng. Sync của giao dịch cũ vẫn kiểm quyền đã cấp, danh tính, ledger và idempotency. Quyền không dùng LWW.

Yêu cầu bàn giao do client sinh UUIDv7, chứa payload hồ sơ không mật khẩu, snapshot phiên bản user/phân công, phạm vi cửa hàng và các máy native phải xác nhận. Khóa toàn tài khoản bởi chủ phải bao quát mọi phân công đang hoạt động; đổi vai trò/khóa phân công bởi quản lý chỉ scope được phép. Web không có lease offline nên không nằm trong tập máy phải ACK. Máy đã thu hồi nhưng từng dùng cloud/giữ dữ liệu không tự coi là đã sạch.

Directory trả các fence đang chờ cho cửa hàng. Native xóa grant cục bộ, khóa đăng nhập cục bộ và hết hạn phiên của user bị fence trong transaction nhận directory, nhưng tiếp tục gửi outbox bằng sync grant cũ. Đã gửi hết outbox và kéo hết feed mới ACK fence, không ACK khi còn queue. Ảnh tùy chọn không phải giao dịch tài chính, tách hàng đợi và vẫn giữ nguyên.

Server cho hoàn tất khi đủ ACK của các máy, snapshot user/phân công chưa đổi và request vẫn pending. Guard trong cùng D1 transaction với cập nhật phân công/user, thu hồi phiên, audit và kết thúc request. Role/self/owner restrictions kiểm lại lúc hoàn tất, không chỉ lúc chuẩn bị. Không tái sử dụng request cũ để ghi đè dữ liệu mới.

Nếu sync grant đã hết hạn trước khi gửi hàng đợi, hủy yêu cầu chuẩn bị, cho nhân viên xác thực online và sync xong rồi lập lại; không tự cấp quyền mới hoặc bỏ outbox. Máy mất/không truy cập được vẫn cần bản sao và đối soát, không có nút “coi như đã gửi hết” tự giải phóng tồn. Thu hồi thiết bị không giải phóng quota bán của máy đó. Đây là ranh giới dữ liệu offline, không cam kết đối soát máy không thu hồi được.

UI danh sách bàn giao hiện từng máy chờ/đã xác nhận, tải lại, hoàn tất hoặc hủy với lý do. Cùng luồng dùng trên native và Web quản lý. Standalone local chưa kết nối cloud vẫn dùng quyền local; không đồng nhất với bảo đảm đa máy cloud.

Test cần có: máy offline chưa ACK chặn hoàn tất; ACK giả/khác scope/queue chưa drain bị chặn; stale snapshot/race rollback; không lộ quyền qua sync token; freeze chặn tương tác nhưng vẫn nhận giao dịch cũ; hủy không tự hồi sinh local grant; toàn tài khoản phải chờ các chi nhánh; Web không bị cấp quota hoặc ACK thay máy native.
