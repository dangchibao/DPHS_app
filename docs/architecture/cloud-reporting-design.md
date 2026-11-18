# Tổng hợp cloud — LEVEL 3, thiết kế triển khai tiếp theo

Worker không tạo PDF hoặc tải cả sổ cái để tính báo cáo. Bảng daily_reports khóa (store_id,day,school_year,school_id), một JSON metric phẳng gồm tổng và các nhóm sản phẩm/size/nhân viên. Giá trị số là chuỗi số nguyên, nhãn có prefix riêng. App/browser cộng BigInt ở client; endpoint đọc theo trang có giới hạn byte/dòng và đúng quyền cửa hàng. Báo cáo native vẫn tính từ SQLite khi offline.

Mỗi mutation tài chính cập nhật summary cùng transaction với ledger/processed mutation/audit. Dùng report_receipts theo document_id với danh sách payment IDs đã áp dụng để chống replay ngay cả khi envelope outbox ID thay. Mỗi lần projector tạo token nội bộ; INSERT OR IGNORE/append payment ID cập nhật last_token chỉ khi chưa áp dụng. UPSERT group chỉ chạy khi receipt.last_token bằng token của request này. Không phụ thuộc changes() giữa nhiều statement. Group gồm dòng/credit/tiền thu snapshot; không tạo marker cho từng dòng hàng, giảm rows written.

UPSERT hợp JSON trong SQLite bằng json_each/group theo key, cộng atomically giá trị hiện hành và delta. Không read-modify-write blob lớn trong Worker, không ghi đè summary theo snapshot client. SQL có kiểm overflow int64 trước cộng; nếu dữ liệu/tổng quá lớn thì đánh dấu summary không thể dùng, không làm thất bại POS. Native BigInt vẫn cho báo cáo chính xác. Không xuất con số đã bị làm tròn.

Dữ liệu cũ trước migration: report_cache_state đánh dấu cần dựng lại ở store có chứng từ cũ; không trả báo cáo thiếu. Rebuild đọc một số ít document/page, dùng cùng projector idempotent, không xóa cache và chạy được khi tiếp tục có giao dịch. Phải giới hạn số request/lượt và backoff/quota; không quét toàn bộ lịch sử trong một request Worker. Store mới/cloud trống không cần rebuild. Import trực tiếp DB phải đánh dấu/dựng lại cache theo runbook.

Nguồn: doanh thu HD/MR và món thay DT trừ credit gốc; giá vốn snapshot và phục hồi khi trả; nhân viên hàng trả là người bán gốc. Tiền thu/hoàn theo ngày payments.created_at. School/year theo snapshot document, không theo lớp hiện tại của học sinh. DH/CK không là doanh thu. Kho hiện tại không gán theo trường; công nợ cloud hiện tại phải ghi nhãn rõ, không giả là số cuối một kỳ lịch sử. Native đã có công nợ lịch sử đúng đến cutoff.

Đọc đa cửa hàng: owner hiện tại + issued owner được xem store bất kỳ/tất cả; manager/accountant chỉ scope đã xác thực. Không tin store list/role từ client. Generic sync không gửi summary cache; native tự tính, Web online đọc RPC.

Đọc phân trang: giữ feed_cursor của trang đầu, sau trang cuối gọi refresh một snapshot SQL để thay thế mọi nhóm bị ảnh hưởng bởi chứng từ/thanh toán mới, gồm nhóm nằm trước keyset cursor. Giới hạn 2000 event/100 nhóm/500KB; vượt thì từ chối và tải lại, không trả báo cáo trộn thời điểm. Kho/công nợ hiện trạng có thời điểm đọc riêng, ghi nhãn rõ. Cache mỗi row giới hạn 250KB trước merge; overflow/row quá lớn đánh dấu, không làm đầy row D1 2MB rồi chặn POS.

Cần kiểm thử: duplicate envelope/cùng document/đồng thời retry không nhân đôi; thu tiền nhiều lần; trả/chênh lệch/giá vốn lớn; group năm/trường/store; migration cũ + rebuild + giao dịch mới; overflow không chặn ledger; rollback projector cùng ledger; API/RPC scope và cursor. Đo lại ước tính D1 toàn module, không tái dùng kết luận schema 16 cho hệ thống mới.
