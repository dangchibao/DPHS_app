# Chuyển kho liên chi nhánh — LEVEL 3, schema 20

Đã có CK xuất với snapshot biến thể/giá vốn, trừ tồn khả dụng máy qua ledger; không chuyển phần đang giữ, không ghi doanh thu/công nợ. Danh sách máy nhận đã duyệt lấy từ directory rồi cache để lập phiếu offline. Vai trò kho/chủ/quản lý dùng quyền stock; API kiểm tra current + issued role, người/máy/cửa hàng và code/ngày/snapshot/số lượng.

Trạng thái suy từ chứng từ và bản ghi append-only: **Đã xuất → Đang chuyển → Đã nhận**. Nguồn xác nhận giao vận chuyển; sau đồng bộ, Worker tạo transfer_offers cho cửa hàng/máy đích. Máy nhận kiểm đếm từng biến thể, kể cả 0, bắt buộc lý do; CK nhận và receipt/stock/audit/outbox cùng transaction. Nhận thiếu/dư ghi rõ chênh lệch; không tự sửa tồn nguồn. Giá vốn giữ snapshot lúc xuất dù catalog đã thay đổi.

Worker tạo transfer_deliveries về nguồn cùng transaction nhận; không mang chứng từ/FK cửa hàng nguồn vào SQLite đích. Client không được push các projection này. Outbox giữ thứ tự causal, receipt đứng trước stock nhập. Gửi lại cùng chứng từ không nhân đôi tồn hoặc biên nhận. Mỗi phiếu được kiểm đếm hoàn tất một lần, không tự nhận bổ sung; sai sót cần đối soát có quyền.

Giao diện menu **Chuyển kho cửa hàng** gồm Phiếu xuất / Hàng chờ nhận, tạo phiếu bằng tìm hàng/mã vạch và nhập lượng; xác nhận giao vận chuyển, nhập thực nhận/lý do, hiển thị lệch. Cập nhật màn hình từ SQLite mỗi 30 giây; không tăng tần suất poll cloud. Giữ cache điểm nhận khi đổi ca sang vai trò không có stock, nhưng mọi lần sử dụng vẫn kiểm quyền.

Kiểm chứng: toàn bộ **134 test Flutter**, **108 test API** đạt; analyze/lint/typecheck/Worker dry-run, migration D1 local 20 đạt. Có UI mobile, nhận thiếu/dư/0, rollback dispatch/projection và nhận/counter, scope/quyền/máy sai, chống ghi projection giả, snapshot cost và replay. Batch 3 CK thử nghiệm nằm trong 50 D1 calls/request.

Smoke HTTP trên workerd/database riêng đạt: bootstrap/login/schema 20, tạo cửa hàng/đăng ký/duyệt máy, seed catalog/nhập kho, CK xuất → dispatch → offer chỉ ở store đích → nhận thiếu → replay → delivery về nguồn. Không deploy cloud, không sửa production. Đây không phải đo CPU Workers production hoặc nghiệm thu máy thật.

Source 0.5.0+5/schema 20; preview ZIP/APK 0.4.0 đã đóng vẫn schema 18, chưa gồm size mới/CK. Chạy thử source: `./scripts/dev.ps1` → đăng nhập kho/chủ/quản lý → menu chuyển kho. Cần có chi nhánh/máy nhận đã đăng ký và dữ liệu điểm nhận đã đồng bộ. Chỉ dùng dữ liệu thử.

Giới hạn: máy nhận phải đúng máy chỉ định; mất/thu hồi máy cần đối soát/bàn giao, chưa có tự chuyển quyền nhận. Khi cloud hết hạn mức, xuất/giao nằm trong outbox; cửa hàng đích thấy offer sau khi cloud nhận được, không có đồng bộ ngang hàng. Không tự hủy/sửa CK đã xuất. Không có PDF CK riêng trong mốc này. Đề xuất: không thêm ngoài phạm vi.
