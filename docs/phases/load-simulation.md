# Mô phỏng tải — schema 30 / 3 cửa hàng / 10 thiết bị

Đã chạy 2026-11-17T07:56:59.844Z. Mô phỏng SQLite dùng cùng migration và hàm push của Workers; không phải benchmark CPU cloud.

900 hóa đơn/ngày (300/cửa hàng), 4 dòng/hóa đơn, 1 thanh toán, 180 đơn đặt cọc, 2 audit client và 1 audit API/hóa đơn. Kiểm tra tổng thu: 306.000.000đ.

|Chỉ số|Kết quả / ước tính|Free|
|---|---:|---:|
|Requests (12 giờ, pull 60 giây, directory + 3 scope, tính bảo thủ mọi máy có quyền audit)|32500|100000|
|Rows read (ngân sách bảo thủ, cần đối chiếu D1 meta)|418460|5000000|
|Rows written cơ sở SQLite, gồm trigger|36000|—|
|Ghi index ước tính theo schema|63183|—|
|Tổng rows written ước tính|99183|100000|
|Dung lượng SQLite của dữ liệu mô phỏng|12046336 bytes|500000000 bytes/database|

Kịch bản sát hạn mức ghi; không đủ phần dư an toàn cho nghiệp vụ thường ngày và backup. Đã gồm tổng hợp tài chính, receipt chống đếm trùng và cache công nợ ban đầu. Còn phải tính các lượt đọc báo cáo, thu nợ tiếp, may/đổi trả/giữ/chuyển kho, chấm công/lương, nhật ký đọc/đăng nhập, quản trị, retry, bookkeeping D1 và dịch vụ dùng chung account. Không chứng minh CPU 10ms bằng thời gian test SQLite; cần profiling Workers trước production.

Bản tính index dùng tăng số entry từng index, có lọc predicate của partial index; chưa phải số đo billing D1. Cần đo meta.rows_written/rows_read và analytics trên môi trường cloud do chủ cấp phép. Kịch bản 8 dòng/hóa đơn, nhiều audit/đổi trả hoặc nghiệp vụ bổ sung có thể vượt Free; không coi phần dư của kịch bản này là ngân sách vận hành an toàn.

Feed nghiệp vụ vẫn giữ toàn bộ để không mất dữ liệu máy offline; schema 30 có compaction audit riêng sau file private verified, phần đó chưa được chạy trong mô phỏng này. Không cam kết dung lượng miễn phí lâu dài: phải đo tăng trưởng và hoàn thiện snapshot/cursor expiry/lưu trữ trước khi bật retention. D1 export cần đo riêng ngoài giờ; không tính là 0 reads khi chưa có bằng chứng.

Nguồn hạn mức: https://developers.cloudflare.com/workers/platform/limits/ ; https://developers.cloudflare.com/d1/platform/pricing/ ; https://developers.cloudflare.com/d1/platform/limits/
