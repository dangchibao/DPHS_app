# Thiết kế đổi trả và hủy bằng chứng từ mới

LEVEL 3. Không sửa/xóa hóa đơn gốc. Chứng từ DT có original_id, dòng nhận lại, dòng hàng thay thế, kho, thanh toán/cấn nợ, audit và outbox cùng transaction. Hủy HD chỉ chủ/quản lý; đổi/trả có quyền riêng cho chủ/quản lý/thu ngân. Không tự động nhận sửa giao dịch cũ từ client.

## Giá trị nhận lại và chống trả vượt

Mỗi return_line tham chiếu invoice_line đã giao (HD hoặc hàng thay thế trên DT). Tổng số lượng trả không vượt số lượng gốc, kiểm tra cả SQLite và D1 bằng trigger. Dùng máy lập chứng từ gốc khi offline để không hai máy cùng hoàn một món.

Giá trị dòng gốc L = quantity × unit_price − discount (giữ cả ưu đãi/combo tại lúc mua). Nếu đã trả a món, nay trả q trong tổng Q, giá trị trả lần này:

`floor(L × (a + q) / Q) − floor(L × a / Q)`

Tính BigInt. Mọi lần trả cộng lại đúng L, không mất tiền do chia lẻ và không hoàn thừa. Dòng trả giữ snapshot tên/size/màu/cost, tham chiếu line_id.

Hàng thay thế khác sản phẩm lấy giá hiện tại đã có revision; đổi size cùng sản phẩm có thể chuyển nguyên giá trị nhận lại sang món mới, không làm mất giảm giá cũ. Phải tham chiếu dòng nhận lại, cùng sản phẩm, số lượng tương ứng; phân bổ giá/giảm dòng bằng số nguyên. API xác minh lại, không tin giá client. Chỉ nhập lại hàng nhận được; mọi xuất/nhập qua stock_movements.

## Thanh toán và công nợ

Gọi B là công nợ còn lại của chứng từ gốc đang nhận hàng trả, R là giá trị nhận lại, N là giá trị hàng thay thế. Cấn nợ C = min(B,R). Tiền cần thu D = N − R + C.

- D >= 0: thu P từ 0 đến D, phần D−P thành công nợ mới trên DT.
- D < 0: hoàn tiền −D bằng payments.direction=refund; không tạo nợ âm.
- C > 0: ghi receivable_adjustments.amount=−C, liên kết DT và chứng từ gốc. Đây là cấn nợ, không tạo khoản thu tiền mặt giả.

Thêm view receivable_ledger hợp nhất receivable_entries và receivable_adjustments cho truy vấn số dư. Trigger bảo đảm cả thu tiền và cấn nợ không làm âm số dư. Không thêm cột vào entries làm hỏng INSERT của các bản trước. Sửa các query số dư/guard có liên quan; paymentHistory vẫn là tiền thực nhận/hoàn, cấn nợ hiển thị riêng.

DT subtotal=total=abs(D), discount=0; metadata giữ R,N,C,D, lý do và loại nghiệp vụ. Dòng hàng thay thế giữ giá trị N, không được suy doanh thu bán mới từ total của DT. Báo cáo sau này dùng biến động hàng/credit và payment direction, tránh cộng nhầm thu/hoàn vào doanh thu.

Cho phép trả tiếp món thay thế từ DT: mỗi dòng vật lý chỉ hoàn một lần theo giới hạn còn lại; công nợ cấn trên chứng từ đã phát hành món đó. original_id nối chuỗi về hóa đơn đầu, không hoàn lại dòng gốc đã trả.

## Hủy hóa đơn

Tạo DT hoàn toàn bộ món còn chưa trả và sự kiện CANCELLED liên kết DT, bắt buộc lý do và quyền voidInvoice. Không nhận hàng thay thế trong luồng hủy. UNIQUE sự kiện hủy theo hóa đơn. Nếu đã trả hết thì báo đã hoàn tất đổi/trả, không tạo phiếu rỗng. Dữ liệu cũ vẫn bất biến.

## Đồng bộ và kiểm thử cần có

Validator DT riêng trước validator HD/MR; bundle nguyên tử gồm doc, return_lines, replacement invoice_lines, stock, payment, entries/adjustments, event hủy. Dependencies chứng từ gốc, danh mục, nhập kho và các lần trả trước. API giới hạn nguồn máy, quyền hiện tại + vai trò tại cấp phiên, tham chiếu cửa hàng, số lượng, giá và cân bằng tiền.

Test: trả từng phần chia lẻ cộng đúng tiền; trả vượt/đồng thời bị chặn; đổi size giữ voucher; đổi khác món thu thêm/hoàn; cấn toàn bộ/một phần nợ; hoàn sau đổi tiếp; retry/power rollback; hủy đúng quyền, kho và nợ; LWW giá thay đổi; export PDF và audit không sửa gốc.
