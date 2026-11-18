# Dashboard và báo cáo local — LEVEL 2/3, schema 23

Menu Dashboard · báo cáo cho chủ/quản lý/kế toán. Dùng SQLite khi mất mạng, lọc ngày (1–366 ngày), năm học và trường. Luôn ghi phạm vi cửa hàng/thời gian đã tải; không giả định dữ liệu local đã gồm mọi cửa hàng.

Đã có doanh thu theo ngày, sản phẩm/lãi gộp, size bán chạy, tồn nhiều/khả dụng, may riêng theo trạng thái cuối kỳ, công nợ/đến hạn cuối kỳ và hiệu suất nhân viên. Dashboard hiện doanh thu thuần/lãi gộp/thu trừ hoàn/công nợ/quá hạn và số chứng từ. DT dùng giá trị món thay và credit hàng trả, không dùng tổng chênh lệch. Giá vốn lấy snapshot lúc bán, trả phục hồi giá vốn gốc. Tiền/tổng dùng BigInt, kể cả vượt 2^53; không chuyển float.

Công nợ lấy số dư đến hết ngày cuối, bao gồm nợ đầu kỳ và không trừ khoản thanh toán sau kỳ. Kho là hiện trạng cửa hàng, không gán cho trường khi mô hình không có kho riêng của trường. Giữ hàng giảm khả dụng, không giảm tồn thực. Đơn may chỉ tính sự kiện tiến độ đã phát sinh trước cuối kỳ.

Đọc dòng bán/đổi/thu tiền theo lô 1000 bằng keyset (timestamp,ID), không OFFSET; hơn 1000 dòng cùng timestamp đã kiểm thử không bỏ/đếm lặp. Có thể hủy khi đóng trang, giảm giữ bộ nhớ và khóa đọc. Màn hình hiện từng 200 dòng, xuất lấy đủ dữ liệu. Index mới payments(store_id,created_at,id) tránh quét lại payments mỗi trang.

Excel/PDF xuất bảng đang chọn với phạm vi cửa hàng/ngày/năm/trường, có audit cùng outbox. Tên file loại ký tự Windows không hợp lệ; số VND quá 15 chữ số xuất Excel dạng text để giữ đủ số, giá trị nhỏ là ô số. PDF A4 ngang dùng font Việt cục bộ. File mẫu đã kiểm tra qua openpyxl đúng số lượng/doanh thu/giá vốn/lãi, render Poppler và kiểm tra trực quan.

Schema 23 cũng thêm private_access_marks để log lần đọc luồng lương đầu phiên/ngày (không tạo log cho mỗi poll); mở trang/xem phiếu có audit riêng. Watermark lương chỉ xét dữ liệu nguồn, tách audit để nhật ký do chính yêu cầu tạo không làm từ chối chốt. Checkpoint máy vẫn xét toàn bộ cursor. Có regression cho trường hợp audit thêm giữa preview và chốt mà nguồn không đổi, bên cạnh race nguồn/cấu hình đổi phải từ chối.

Kiểm chứng: 174 test Flutter toàn bộ đạt; kiểm thử API 129 đạt/typecheck/lint. Các mốc sau đã xác nhận analyze sạch, 195 test Flutter và Windows/Web schema 27 build đạt; xem staff-handoff.md và media-bank-usage.md. Trước đó nhóm 8 test báo cáo local/service/UI/export đạt, có rollback/quyền/cách ly store, lọc trường/năm, giữ hàng, trạng thái may theo kỳ, công nợ sau kỳ, phân trang 1001 dòng, giá vốn snapshot rất lớn. D1 local migration 23 đã đạt; Worker dry-run đang được kiểm tra.

Source 0.6.0+6/schema 23 chưa đóng gói; ZIP/APK 0.5.0 vẫn schema 21. Chạy ./scripts/dev.ps1 → vai trò reports → Dashboard · báo cáo. Chỉ dữ liệu thử. Cloud tổng hợp toàn hệ thống và Web online là bước kế tiếp; chưa tuyên bố hoàn tất toàn bộ báo cáo đa cửa hàng.

Đề xuất: không bổ sung ngoài phạm vi.

Cloud tổng hợp và Web online đã bổ sung ở schema 24–29; xem reports-cloud-web.md và store-settings-web-management.md. Những số đếm schema 23 trên đây ghi mốc lịch sử.
