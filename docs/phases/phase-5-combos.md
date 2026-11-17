# Phase 5 — combo và củng cố đồng bộ

Mốc phát triển ngày 15/11/2026, schema 12. Chưa kết thúc toàn bộ phase 5: giá trường/đại lý, khuyến mãi/voucher vẫn cần triển khai.

## Chức năng

- Chủ/quản lý tạo, sửa, ngừng combo theo cửa hàng; giá bộ riêng và số lượng từng sản phẩm thành phần. POS chọn size/màu riêng từng món, nhiều bộ và thêm hàng lẻ trong cùng giỏ. Trừ kho từng biến thể thực tế.
- Tính tiền nguyên bằng BigInt, phân bổ giá bộ theo trọng số và phần dư lớn nhất. Dòng hàng có giá đơn vị làm tròn lên và giảm dòng bù số dư, giữ đúng tổng VND kể cả chia không hết. PDF thể hiện giảm dòng.
- Snapshot tên/giá/thành phần combo trong hóa đơn; lịch sử revision append-only. API tính lại từ revision được duyệt, không tin giá combo trong payload client.
- Giữ đơn tạm lưu cả lựa chọn combo; mở rồi giữ lại cập nhật cùng đơn. Ràng buộc một đơn tạm chỉ phát hành một hóa đơn. Đối soát restore dọn các đơn tạm đã có hóa đơn trên cloud.
- Outbox có dependency combo/danh mục trước hóa đơn và nhập kho trước giao dịch phụ thuộc. API dùng con trỏ audit riêng; thu ngân không nhận nhật ký nhạy cảm, quản lý vào ca sau vẫn kéo đủ log.
- Server ghi thời điểm tiếp nhận audit, gửi lặp giữ lần tiếp nhận đầu. Client lưu biên nhận riêng cho log đã có, không sửa bản ghi append-only hoặc hash gốc. Phiên sync lưu sau logout chỉ dùng đẩy hàng đợi, không dùng đọc dữ liệu.
- Đăng nhập offline có thể tự xác thực lại khi mạng trở lại bằng proof trong RAM; không lưu mật khẩu/proof vào database hoặc secure storage. Salt đã đổi yêu cầu đăng nhập lại. Đúng mật khẩu cũ nhưng cloud từ chối sẽ xóa lease offline; nhập nhầm mật khẩu không phá lease. Phát hiện bản sao thiết bị lưu khóa nghiệp vụ.
- Sửa parser migration để giữ dấu chấm phẩy trong chuỗi/comment. Có regression test và nâng cấp từ schema 1.

## Kiểm chứng

- API: 36 test đạt; typecheck đạt. Bao gồm xác minh giá combo, quyền, gửi lặp audit, timestamp do server cấp và cursor audit độc lập.
- Flutter: toàn bộ 53 test đạt và analyze đạt. Bao gồm nghiệp vụ combo/giá/POS, đăng nhập lại, thu hồi lease, biên nhận audit, migration, backup và PDF. Windows release và APK 0.2.0 build thành công; APK ký debug, xác minh v2 và quyền Internet. Chưa nghiệm thu Android trên máy thật.
- Smoke test HTTP với workerd local/schema 12 đạt bootstrap/challenge/login và từ chối credential sai. Worker dry-run đạt; không deploy cloud.
- Mô phỏng 900 hóa đơn/ngày × 4 dòng, 3 cửa hàng/10 máy: 32.500 request, 328.460 rows read, 92.340 rows written ước tính; tính bảo thủ cả 10 máy kéo audit. Đây không phải billing hoặc benchmark CPU cloud.

## Chạy thử

Chạy `./scripts/dev.ps1`. Menu → Combo đồng phục để cấu hình; tại POS bấm chọn combo, chọn size/màu từng món rồi thêm vào giỏ. Kiểm tra giá bộ, thanh toán và xem PDF. Dữ liệu khởi tạo mới có combo mẫu; database cũ không bị tự thêm dữ liệu mẫu.

## Đề xuất

Không thêm tính năng ngoài phạm vi. Chưa nghiệm thu trên hai máy thật, máy quét/máy in thật hoặc D1 production; tiếp tục giá riêng/khuyến mãi và các module còn lại theo kế hoạch.
