# Mô phỏng tải — 3 cửa hàng / 10 thiết bị

Đã chạy 2026-11-15T15:12:59.531Z. Mô phỏng SQLite dùng cùng migration và hàm push của Workers; không phải benchmark CPU cloud.

900 hóa đơn/ngày (300/cửa hàng), 4 dòng/hóa đơn, 1 thanh toán, 180 đơn đặt cọc, 2 audit client và 1 audit API/hóa đơn. Kiểm tra tổng thu: 306.000.000đ.

|Chỉ số|Kết quả / ước tính|Free|
|---|---:|---:|
|Requests (12 giờ, pull 60 giây, directory + 3 scope, tính bảo thủ mọi máy có quyền audit)|32500|100000|
|Rows read (ngân sách bảo thủ, cần đối chiếu D1 meta)|328460|5000000|
|Rows written cơ sở SQLite, gồm trigger|34020|—|
|Ghi index ước tính theo schema|58320|—|
|Tổng rows written ước tính|92340|100000|
|Dung lượng SQLite của dữ liệu mô phỏng|11067392 bytes|500000000 bytes/database|

Kịch bản cơ sở nằm trong ngân sách ghi ước tính. Còn phải tính báo cáo tổng hợp, quản trị, các lần ghi retry, bookkeeping nội bộ D1 và dịch vụ khác dùng chung account. Không chứng minh CPU 10ms bằng thời gian test SQLite; cần profiling Workers trước production.

Bản tính index dùng tăng số entry từng index, có lọc predicate của partial index; chưa phải số đo billing D1. Cần đo meta.rows_written/rows_read và analytics trên môi trường cloud do chủ cấp phép. Kịch bản 8 dòng/hóa đơn, nhiều audit/đổi trả hoặc thêm bảng tổng hợp có thể vượt Free.

Change feed đang lưu toàn bộ để chưa làm mất dữ liệu thiết bị offline. Không cam kết dung lượng miễn phí lâu dài: phải đo tăng trưởng và hoàn thiện snapshot/cursor expiry/lưu trữ trước khi bật retention. D1 export cần đo riêng ngoài giờ; không tính là 0 reads khi chưa có bằng chứng.

Nguồn hạn mức: https://developers.cloudflare.com/workers/platform/limits/ ; https://developers.cloudflare.com/d1/platform/pricing/ ; https://developers.cloudflare.com/d1/platform/limits/
