# Chuyển kho CK — thiết kế đã triển khai schema 20 (LEVEL 3)

Nguồn tạo CK kind transfer_out, total/subtotal/discount=0, customer/original null. invoice_lines snapshot unit_price=0, unit_cost theo revision, quantity; stock transfer_out âm. Header metadata target_store_id/device_id/code + notes. Chỉ khác store, máy nhận approved được cache từ directory. Client UUIDv7, mã CK/counter cùng transaction; ngày mã lấy từ issued_at đã chốt, kể cả transaction qua nửa đêm.

transfer_events chỉ sự kiện dispatch, append-only, unique(store_id,document_id), gắn máy tạo CK. Tạo sau CK. Đồng bộ dispatch mới tạo projection transfer_offers ở store đích, máy nhận chỉ định, id=UUID CK nguồn. Projection chứa source ids/codes, ngày xuất/chuyển, năm học, items_json snapshot và ghi chú. Không kéo document/FK cửa hàng nguồn sang SQLite đích. Không cho client push projection.

Đích lập CK kind transfer_in và transfer_receipts id=UUID CK nhận, unique(store_id,offer_id). counts_json đủ mọi variant trong offer, mỗi actual 0..100000; lý do bắt buộc, chênh lệch hiển thị rõ. invoice_lines và stock transfer_in chỉ phần actual>0; cho nhận 0 toàn bộ với lý do. unit_cost theo offer, không đổi theo giá catalog sau xuất. Máy khác không được nhận offline. Receipt/header/lines/stock/audit/outbox nguyên tử.

Worker xác minh receipt, tạo projection transfer_deliveries về store nguồn, id=CK nhận, chứa nguồn/đích, code, người nhận/time/counts/reason. Không sửa kho nguồn. Trạng thái nguồn suy từ CK xuất → dispatch → delivery: Đã xuất / Đang chuyển / Đã nhận. Chênh lệch không tự sửa ledger nguồn; kiểm kê riêng có quyền. Cho thực nhận vượt số xuất nhưng phải reason/audit, thể hiện phần lệch; không coi là doanh thu.

API validateTransfers trước validateSales, trả Set CK để skip luồng HD/MR nhưng vẫn kiểm child cohesion, permission stock, actor/current+issued roles, device/store, code/date, exact counts/movements/snapshot, no payments/debt/customer. Dispatch mutation chỉ event/audit; receipt cần CK cùng bundle. Immutable gate chặn thêm child vào CK đã phát, kể cả receipt.id=CK.id. Projection statements/feed cùng batch với event/receipt và processed mutation để không có cửa sổ nửa giao dịch.

Outbox transfer_out: doc/lines/stock; transfer_dispatch: event, phụ thuộc CK xuất; transfer_in: doc/lines/receipt trước stock. Giữ causal dependency kho/bán/đổi/giữ trước thao tác âm. Directory thêm danh sách điểm nhận tối thiểu cho vai trò stock; cache local_settings, không nhập foreign stores/devices thành danh tính máy hiện tại. Pull whitelist projection; push allowlist chỉ event/receipt do client tạo.

Test: hai store/device; đúng trạng thái; hàng giữ bảo vệ xuất; xuất/nhận retry không nhân đôi; actor/role/scope/máy đích sai; lệch/nhận 0; không sửa nguồn; catalog thay giá giữa chặng vẫn cost snapshot; rollback/counter/midnight; restore/cursor; API projections và D1 batch/Free budget; UI nhập/giao nhận. Mất/thu hồi máy cần bàn giao có đối soát ở module riêng, không auto nhận lại quyền tồn.

Hiện source schema 19 chưa có CK hoạt động. Chỉ bổ sung schema/module sau thiết kế này; không đánh dấu hoàn thành trước test.
