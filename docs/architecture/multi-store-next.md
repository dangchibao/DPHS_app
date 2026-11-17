Đăng ký/duyệt/thu hồi máy và tạo chi nhánh đã có tại schema 18; xem phase-7-device-enrollment.md. Mô tả dưới đây được giữ cho các yêu cầu vận hành đầy đủ, đặc biệt chuyển kho/bàn giao quyền. Mặc định CN01/A2 hiện chỉ còn ở đường khởi tạo dữ liệu thử; máy đăng ký qua API dùng danh tính động.

# Vận hành nhiều cửa hàng / chuyển kho — tiến độ và phần tiếp theo

Onboarding động đã triển khai cho bản cài trống tại schema 18. Còn hoàn thiện provision chủ đầu tiên, bàn giao phân công/quyền bán và chuyển kho trước production. Máy khởi tạo dữ liệu thử vẫn dùng CN01/A2; không dùng đường thử nghiệm để vận hành nhiều máy thật.

Máy bán thuộc một store; owner quản trị store khác qua API online, không mượn thiết bị cửa hàng này để bán kho cửa hàng kia. Directory cho người vận hành chỉ thêm danh sách điểm/máy nhận chuyển kho tối thiểu, không lộ lương. Backend/SQLite tiếp tục store scope.

CK xuất ở store nguồn: doc CK kind=transfer_out, snapshot dòng/cost, stock_movements transfer_out. Chọn store + máy nhận đã duyệt, lý do. Đã xuất → SHIPPED event append-only → Đang chuyển. Nguồn cần đủ phân bổ chưa giữ; outbox causal với catalog, stock và giữ hàng.

Khi server nhận CK, tạo projection incoming_transfers chỉ đọc, store_id đích, id dùng lại UUID client nguồn, snapshot mã nguồn/dòng/cost/máy nhận. Khi SHIPPED, mirror event đích store-scoped. Không ép dest client lưu documents của store nguồn vì FK/scope local phải đúng. Projection không được client tự push.

Đích nhận trên máy được chỉ định (ngăn nhận hai lần khi nhiều máy offline): CK kind=transfer_in và UUID/mã của đích, original_id=NULL; metadata tham chiếu incoming_offer id/mã nguồn. incoming_receipts unique(store_id,offer_id), thực nhận từng biến thể kể cả 0, lý do bắt buộc khi chênh lệch; stock_movements transfer_in chỉ số nhận thật. Worker xác minh offer/máy/trạng thái, mirror receipt về store nguồn để hiển thị Đã nhận. Các projection/event dùng id client có sẵn, không server cấp số chứng từ.

Chênh lệch không tự sửa kho nguồn bằng quyền kho đích. Ghi rõ số xuất/nhận/lệch và audit; nguồn kiểm kê/điều chỉnh riêng có quyền. Tổng tồn cửa hàng tách với hàng đang chuyển. Cấp/bàn giao quyền nhận khi máy mất/thu hồi cần owner online và đối soát, không đổi ngầm quyền thiết bị đang giữ giao dịch offline.

Mọi ghi CK/stock/events/outbox nguyên tử, giá trị tài chính CK=0; không cộng CK vào doanh thu/công nợ. Invoice_lines có thể chứa snapshot chuyển kho nhưng báo cáo phải lọc HD/MR/DT. API validator CK riêng, batch trong Free, replay không tăng kho hai lần. Test hai store/device, sai scope, kho/giữ không đủ, thứ tự xuất/chuyển/nhận, thiếu/dư, máy sai, retry và restore.

Chưa deploy, chưa tạo tài khoản cloud hoặc dùng phí. Chỉ yêu cầu chủ cung cấp tài khoản/thao tác ngoài môi trường khi phần triển khai đã cụ thể và kiểm chứng local.
