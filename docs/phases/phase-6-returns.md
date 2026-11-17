# Phase 6 — đổi size, đổi trả và hủy HD

Source nghiệp vụ schema 15; schema 16 bổ sung sửa giới hạn D1 Free. Đây là một phần phase 6, chưa có giữ hàng/chuyển kho hoàn chỉnh.

## Đã làm

- Chọn hóa đơn hoặc phiếu đổi trước đó còn hàng, nhập số lượng/lý do, nhận lại hoặc đổi sang sản phẩm khác. Giá trị nhận lại giữ đúng snapshot sau combo/ưu đãi, tính phần lẻ theo tích lũy; trả hết cộng lại đúng tổng gốc.
- Đổi size cùng sản phẩm có tùy chọn giữ giá sau ưu đãi cũ. Món khác theo revision giá hiện tại; gộp dòng cùng biến thể bằng giá/giảm dòng nguyên VND. Có thể trả tiếp hàng đã đổi; không hoàn trùng dòng gốc.
- DT có mã branch/device/ngày, liên kết original_id. Nhập hàng nhận lại và xuất hàng thay thế qua sổ cái; quyền bán của thiết bị được kiểm tra. Kho thiếu hoặc bất kỳ lỗi giữa transaction đều rollback DT/kho/nợ/counter.
- Cấn nợ bằng receivable_adjustments, tách tiền thực thu/hoàn; view receivable_ledger giữ số dư thống nhất. Thu vượt số nợ sau cấn bị chặn ở cả service và trigger. Phần chênh lệch chưa thu thành nợ mới trên DT; không tạo nợ âm hoặc thu tiền mặt giả.
- Chủ/quản lý có quyền hủy HD riêng: nhận toàn bộ món còn lại, lập DT và sự kiện CANCELLED, không sửa/xóa HD gốc. Thu ngân được đổi/trả, không hủy HD. Nhận trả offline dùng máy lập chứng từ gốc.
- Hàng đợi giữ dependency hóa đơn gốc, lần trả/thu tiền trước, catalog/nhập kho. Gửi lặp không nhân đôi. API xác minh lại số lượng/giá/cấn nợ/thu hoàn; không cho thêm dòng vào DT đã phát hành.
- Màn mobile chọn hàng/số lượng, xem chênh lệch, lý do và phương thức thu/hoàn. PDF DT A5 tách hàng nhận lại, hàng thay thế, cấn nợ và tiền hoàn. Lịch sử nợ hiển thị cấn từ DT riêng; từ nhật ký HD tìm được thao tác liên quan qua original_id.

## Kiểm chứng

Mốc đầu: toàn bộ 106 test Flutter và 83 test API đạt; có rollback lỗi ghi kho giữa transaction, chia lẻ, giữ giá khi đổi size, trả tiếp hàng đổi, thu sau cấn, hủy đúng quyền, UI mobile và PDF. Đã render/kiểm tra trực quan phiếu đo A4 và phiếu DT A5: một trang cho dữ liệu mẫu, font tiếng Việt đúng, không bị cắt hoặc tràn.

Sau đó bổ sung test D1 Free cho payload cũ 5 mutation ack 3+2, kiểm soát 50 calls và JSON 32 đối số; test mục tiêu đạt. Số test tích hợp/build cuối cùng ghi ở progress.md.

## Chạy thử

`./scripts/dev.ps1` → menu **Đổi size · đổi trả**. Tìm hóa đơn, nhập số lượng nhận lại. Chọn hàng thay thế và giữ giá nếu đổi size cùng sản phẩm. Kiểm tra cấn nợ, số cần thu/hoàn; nhập lý do rồi xác nhận. Tab **Phiếu đổi/trả** xem PDF. Hủy HD ở nút riêng chỉ chủ/quản lý thấy.

Gói preview 0.2.0 cũ ở schema 12 chưa gồm phần này. Dùng source hiện hành để thử. Chưa triển khai cloud; chưa dùng dữ liệu thật.

## Giới hạn và đề xuất

Luồng này nhận lại hàng bán sẵn trên HD/DT; MR không tự nhập vào kho đồng phục bán sẵn. Chưa hỗ trợ bàn giao quyền hoàn/thu sang máy khác. Phiếu quá lớn phải chia theo thông báo giới hạn đồng bộ. Báo cáo sau này phải tính riêng giá trị hàng nhận lại/hàng thay thế; không cộng total DT như doanh thu bán mới. Không thêm tính năng ngoài danh sách đã duyệt.
