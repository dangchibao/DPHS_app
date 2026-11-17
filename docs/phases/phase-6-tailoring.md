# Phase 6 — mốc đơn may riêng

Source schema 14. Đây là một phần phase 6; đổi trả, giữ hàng và chuyển kho còn phải làm.

## Đã làm

- Phiếu MR có mã cửa hàng/thiết bị/ngày, snapshot mẫu sản phẩm, giá vốn/giá bán, số đo và yêu cầu riêng. Có ngày hẹn, ghi chú, chọn khách/học sinh đã có và công nợ đúng phụ huynh.
- Số đo nhập cm/kg, lưu mm/gram nguyên: ngực, eo, mông, dài áo/quần, vai, chiều cao, cân nặng. Chặn thiếu số đo, số âm, vượt giới hạn và tràn khi đổi đơn vị.
- Bảng phụ thu do chủ/quản lý cấu hình: phí cơ bản mỗi món, mỗi bậc vượt ngưỡng số đo làm tròn lên, yêu cầu như may gấp/thêm túi/đổi cổ. Không hard-code mức thu. Tổng bằng BigInt, có lịch sử revision để API xác minh sau bán offline.
- Trạng thái Mới nhận → Đang may → Xong → Đã giao bằng document_events append-only, unique/trigger chặn nhảy và lặp bước. Nhân viên kho có quyền cập nhật tiến độ; không có quyền thu tiền hoặc sửa bảng giá. Cập nhật offline dùng máy lập phiếu để giữ thứ tự.
- Đặt cọc/thu thêm/tất toán dùng payments và sổ công nợ. Ngày hẹn đồng thời là hạn công nợ ban đầu; có lịch sử thu riêng. Phiếu MR không trừ hàng bán sẵn và chưa quản lý nguyên liệu vải (không thuộc danh sách yêu cầu).
- Phiếu đo PDF tiếng Việt dùng font offline, in số đo, phụ thu, yêu cầu, hẹn trả và đặt cọc. Hàng đợi có dependency trước phiếu và trước sự kiện; gửi lại không nhân đôi.

## Kiểm chứng

89 test Flutter, 69 test API đạt; analyze, API lint/typecheck, Worker dry-run và mô phỏng tải cơ sở đạt. Bao gồm vector phụ thu chung Dart/TypeScript, snapshot/retry, không thay đổi kho hàng sẵn, thu nợ MR, liên kết học sinh, thứ tự trạng thái, UI mobile và PDF.

## Chạy thử

`./scripts/dev.ps1` → menu **Đơn may riêng**. Chủ/quản lý mở **Bảng phụ thu**, tạo cấu hình. Chọn **Nhận đơn may**, mẫu sản phẩm, đủ số đo, yêu cầu, hẹn trả và số tiền đã nhận. Từ danh sách chuyển từng bước hoặc xem phiếu đo PDF. Thu thêm tiền tại **Đặt cọc & công nợ**.

Giao diện hiện nhận một mẫu sản phẩm mỗi phiếu; service/API có thể nhận tối đa 20 mẫu dùng chung bộ số đo. Giá vốn là snapshot mẫu gốc, chưa phải tính giá thành sản xuất chi tiết. Gói preview 0.2.0 cũ ở schema 12, chưa có mốc này.

## Đề xuất

Không bổ sung ngoài phạm vi. Nghiệm thu thiết bị thật, PDF bản in, cập nhật tiến độ trên nhiều máy có bàn giao quyền và D1 production được thực hiện ở mốc tích hợp tiếp theo.
