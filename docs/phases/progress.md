# Tiến độ kiểm chứng — 16/11/2026

Người dùng đã cho phép tiếp tục tự động giữa các phase. Đây là mốc tích hợp đang phát triển, chưa phải nghiệm thu toàn bộ yêu cầu và chưa dùng cho dữ liệu thật.

## Nền tảng local, quyền và kho

Đã có đăng nhập tiếng Việt, mật khẩu bootstrap qua môi trường, quyền theo vai trò ở service/API, thời hạn offline 7 ngày không tự gia hạn, tạo/sửa/khóa nhân viên. Quản lý chỉ khóa phân công ở cửa hàng của mình; chủ có thể khóa tài khoản toàn hệ thống. Khóa thay cho xóa hồ sơ đã có giao dịch.

Đã có sản phẩm/biến thể, size/màu, SKU/mã vạch, năm học, giá vốn/giá bán, ngưỡng sắp hết, ngừng bán; điều chỉnh có lý do, sổ cái và cache tồn, phân bổ quyền bán theo thiết bị. Đã có bảng quy đổi/gợi ý size cấu hình ở source schema 19; ảnh sản phẩm và kiểm kê phối hợp nhiều máy còn thiếu.

## Đồng bộ

Đã có outbox chụp nguyên dữ liệu cùng transaction, dependency giữa danh mục/hóa đơn/thu tiền, batch xử lý tối đa 3 thay đổi (API nhận payload cũ 5 và ack từng phần), cursor có index, LWW deterministic cho danh mục, idempotency theo ID và nội dung, kiểm tra bundle hóa đơn, quyền và phạm vi cửa hàng. Giữ mọi phiên bản giá được duyệt, kể cả revision thua LWW, để xác minh hóa đơn offline.

Phiên đồng bộ riêng theo người tạo được lưu trong secure storage, giúp đổi ca không gửi nhầm danh tính. Retry có backoff/jitter, poll 60 giây, trạng thái mất mạng/cloud giới hạn/xung đột. Quota ngày được thử lại sau 00:00 UTC. Đăng nhập offline có thể tự nối lại khi có mạng bằng proof trong RAM, không lưu mật khẩu; đổi salt yêu cầu đăng nhập lại. Phải đăng nhập lại đúng người nếu quyền gửi hàng đợi của người đó hết hạn; không bỏ giao dịch.

Schema có cửa hàng/thiết bị và ràng buộc phạm vi; màn vận hành nhiều cửa hàng, duyệt/thu hồi thiết bị và chuyển phân bổ tồn chưa hoàn thiện. Cấu hình D1 hiện là local. Chưa đo CPU/billing cloud hoặc nghiệm thu đồng bộ trên hai thiết bị thật. Xem load-simulation.md để biết ước tính và khoảng trống ngân sách Free.

## POS, hóa đơn và công nợ

Đã có tìm/nhập mã HID liên tục, giỏ, số lượng, giá được kiểm tra lại khi thanh toán, giảm giá theo quyền, tiền mặt/chuyển khoản, tiền thừa, đặt cọc, giữ đơn tạm, snapshot dòng hàng/giá vốn, PDF tiếng Việt offline và tem Code128 theo khổ cấu hình. Mã HD có chi nhánh/thiết bị/ngày; counter và ghi hóa đơn cùng transaction.

Đã có danh sách nợ, lọc quá hạn, lịch sử thu, thu nhiều lần và tất toán bằng bút toán mới. Chặn thu vượt nợ tại SQLite/D1, gửi lặp không thu hai lần. Luồng thu offline giới hạn ở thiết bị lập hóa đơn để tránh hai thiết bị cùng thu trên số nợ cũ. Chưa có bàn giao quyền thu sang thiết bị khác. Đã có combo chọn size/màu từng món và giá bộ, giữ snapshot và trừ tồn từng thành phần. Đã có DT đổi/trả, giữ giá sau ưu đãi khi đổi size, cấn nợ/thu hoàn riêng và hủy HD bằng chứng từ mới. QR ngân hàng vẫn cần cấu hình hoàn chỉnh.

## Trường, lớp và học sinh

Source schema 13 đã có thêm/sửa/ngừng theo dõi trường, lớp/niên khóa, học sinh, phụ huynh; POS gắn học sinh hoặc đơn tập thể; dùng lại khách hàng và giữ snapshot trên hóa đơn/PDF. Có lịch sử mua theo học sinh và dữ liệu mẫu khi khởi tạo mới. Xem phase-5-schools.md. ZIP/APK 0.1.0-preview trước đó ở schema 9 chưa gồm màn này; bản 0.2.0-preview dùng schema 12.

## Giá riêng và khuyến mãi

Source schema 13 có bảng giá trường/đại lý theo biến thể, danh bạ đại lý, giảm cố định/phần trăm/voucher, ngưỡng số món/tiền và ngày áp dụng; mặc định không cộng dồn. Hóa đơn giữ revision; API tính lại từ lịch sử được duyệt. 74 test Flutter và 57 test API đạt, analyze/typecheck/lint/Worker dry-run đạt. Xem phase-5-commercial.md. Gói preview 0.2.0 trước đó vẫn ở schema 12.

## May riêng

Source schema 14 có phiếu MR/số đo/phụ thu cấu hình, hẹn trả, trạng thái append-only, đặt cọc/thu nợ và phiếu đo PDF; không trừ kho hàng sẵn. 89 test Flutter và 69 test API đạt. Xem phase-6-tailoring.md. Bản ZIP/APK 0.2.0 trước đó chưa gồm phần này.

## Đổi size, đổi trả và hủy HD

Source schema 15/16 có DT nhận lại/đổi hàng, giữ giá sau ưu đãi khi đổi size, cấn nợ/thu hoàn, công nợ mới, hủy HD đúng quyền và PDF. 106 test Flutter và 83 test API đạt ở mốc đầu; bổ sung kiểm thử D1 Free sau đó. Xem phase-6-returns.md. Gói preview 0.2.0 trước đó vẫn schema 12.

## Nhật ký, sao lưu và xuất dữ liệu

Đã có audit append-only/hash chain, biên nhận cloud không sửa hash gốc, cursor riêng cho chủ/quản lý, tìm theo người/máy/mã/chứng từ/thời gian/mức độ, xem chi tiết và xuất XLSX/PDF; từ hóa đơn có đường dẫn lịch sử. XLSX thật, giữ tiền nguyên và chuỗi bắt đầu bằng `=` dưới dạng văn bản.

Đã có snapshot SQLite khi đang mở, integrity/SHA256, ZIP và AES-GCM tùy chọn, cấu hình giờ/thư mục/rotation, sao lưu bù lịch/khi thoát/trước nâng cấp, diễn tập kiểm tra hàng tuần. Android chạy nền/thoát cưỡng bức không bảo đảm thực thi đúng giờ; ứng dụng bù lịch khi mở lại.

Restore kiểm tra mật khẩu/checksum/danh tính, xác nhận hai lần và lý do; backup hiện trạng, giữ outbox/audit, từ chối nhánh audit hoặc hàng đợi cùng ID khác nội dung. Có journal phục hồi thao tác đổi file khi khởi động lại. Chặn nghiệp vụ đến khi kéo hết cloud và nâng counter. Chưa nghiệm thu mọi tình huống mất điện thật, backup cloud mã hóa, retention cloud hoặc cảnh báo tổng hợp toàn hệ thống.

## Chức năng còn lại

- Hoàn thiện bàn giao nhân viên giữa cửa hàng và phân bổ/chuyển tồn an toàn; đăng ký/duyệt/thu hồi máy và tạo chi nhánh đã có ở source 18.
- Nghiệm thu tích hợp trường/học sinh/combo/ưu đãi trên thiết bị thật và D1.
- Nghiệm thu chuyển kho/giữ hàng/may riêng/đổi trả trên thiết bị thật và quy trình bàn giao khi máy mất/thu hồi.
- Hoàn thiện bảng lương/phiếu lương, dashboard và báo cáo; Web/PWA quản lý online. Hồ sơ/phân quyền và chấm công đã có; công thức lương đã kiểm thử riêng, chưa phát hành kỳ.
- Backup cloud, telemetry hạn mức thực tế, nghiệm thu bảo mật/tải/restore, hướng dẫn và bộ cài cuối cùng.

## Chạy thử hiện tại

Ở gốc repository chạy `./scripts/dev.ps1`. Script đọc `.env`, migrate D1 local và mở Flutter. Tài khoản admin dùng mật khẩu đã cấu hình trong `.env`; không có mật khẩu mặc định trong source. Kiểm tra bằng `./scripts/check.ps1`; mô phỏng tải bằng `cd api; npm run simulate`.

Kiểm thử bao phủ kho, mã chứng từ/rollback, snapshot, giá LWW, quyền/phiên, outbox theo nhân viên, reconcile sau restore, PDF/tem, thanh toán/công nợ và XLSX. Báo cáo số test/build chỉ áp dụng cho lệnh đã chạy thành công ở mốc tương ứng, không thay cho nghiệm thu các mục còn thiếu.

## Mốc kiểm chứng 0.2.0

53 test Flutter và 36 test API đạt; Flutter analyze, API lint/typecheck và Worker dry-run đạt. Nâng D1 local qua migration 12 thành công. Windows release và Android APK 0.2.0 (versionCode 2) đã build thành công. APK xác minh chữ ký v2 và quyền Internet; vẫn ký bằng khóa debug. Smoke test HTTP trên runtime workerd local đạt bootstrap/challenge/login/từ chối credential sai/schema 12. Xem phase-5-combos.md để biết phạm vi; không coi đây là nghiệm thu toàn bộ phase 5.

Sau mốc đóng gói đã kiểm tra thêm nâng schema 9 → 12 với hóa đơn, đặt cọc/công nợ, sổ cái kho, bộ đếm và hàng đợi đang có: giữ nguyên dữ liệu và ràng buộc hóa đơn bất biến. Tổng cộng 54 ca Flutter đã đạt (53 ca toàn bộ + 1 regression nâng cấp bổ sung). Web release biên dịch thành công, nhưng màn quản lý online vẫn chưa hoàn thiện. ZIP đã xác minh 36 file theo manifest; ZIP/APK đều có migration 12 và SHA256 khớp.

## Mốc 0.3.0 / schema 16

Đã build Windows release 0.3.0+3. API 86 test đạt, lint/typecheck/dry-run và mô phỏng đạt. Flutter toàn bộ 106 test đạt ở mốc nghiệp vụ; nhóm 14 test migration/auth/sync/đổi trả và analyze đạt sau sửa D1 Free/schema 16. Hạn mức đọc/ghi mô phỏng vẫn là ước tính, chưa benchmark CPU cloud. Đã tạo ZIP Windows và APK 0.3.0-preview; kiểm tra 40 file ZIP theo manifest, SHA256 cả hai gói, schema 16 trong assets. APK xác minh chữ ký v2, versionCode 3 và quyền Internet; vẫn ký debug. Toàn bộ 106 test Flutter chạy lại đạt sau đóng gói; smoke HTTP workerd/schema 16 đạt. Chưa deploy.

## Đề xuất

Không bổ sung tính năng ngoài phạm vi đã duyệt. Cần đo D1 thực tế trước production: mô phỏng bảo thủ hiện chỉ còn khoảng 7,7% ngân sách ghi ở mức 900 hóa đơn/ngày × 4 dòng, chưa gồm tất cả module.


## Mốc source 0.4.0 — schema 18

Giữ hàng DH có hạn, tồn khả dụng, giải phóng/giao qua HD atomic; quản trị tạo chi nhánh, đăng ký/duyệt/thu hồi máy và phân công mới vào chi nhánh; danh tính/endpoint động trên bản cài mới. Có sửa lịch sử backup trước nâng cấp và kế thừa cấu hình mã hóa. Toàn bộ 119 test Flutter và 96 test API đạt; API lint/typecheck/Worker dry-run và Flutter analyze đạt. Smoke HTTP workerd trên database riêng đạt bootstrap/challenge/login/từ chối credential sai/schema 18; tạo chi nhánh/mời/claim máy/chặn bản cài khác/duyệt/đăng nhập tại chi nhánh mới đều đạt. Windows 0.4.0+4 build đạt, đã xác minh EXE và migration 18. APK 0.4.0 (versionCode 4) build đạt, chữ ký v2/Internet/3 kiến trúc và asset schema 18 đã kiểm tra; preview 0.3.0 trước đó vẫn schema 16. Xem phase-6-reservations.md, phase-7-device-enrollment.md và backup-upgrade-review.md. Chưa có chuyển kho, lương/báo cáo/Web quản lý hoàn chỉnh; chưa deploy cloud.


## Mốc source schema 19 — bảng size

Bảng size theo sản phẩm/dùng chung trong cửa hàng, khoảng cao/nặng cấu hình, gợi ý tất cả size khớp và UI mobile. Toàn bộ 128 test Flutter và 103 test API đạt; Flutter analyze, API lint/typecheck/dry-run và migration D1 local 19 đạt. Xem size-rules.md. Source đang ở 0.5.0+5; chưa đóng gói 0.5.0. Gói 0.4.0 đã kiểm tra 42 file manifest/ZIP và checksum ZIP/APK, vẫn schema 18. Web 0.4.0 build đạt nhưng chức năng quản lý online vẫn chưa triển khai; không coi build là nghiệm thu Web.


Sau mốc schema 19 bổ sung sửa ngày mã chứng từ: counter/code lấy mốc issued_at thay vì đọc clock lần nữa khi đã qua nửa đêm Việt Nam. 20 test nghiệp vụ liên quan đạt, có regression cả 5 loại mã HD/MR/DH/DT/CK reset ngày độc lập. Chuyển kho đang ở thiết kế transfers-implementation.md, chưa triển khai nghiệp vụ CK.


## Mốc source schema 20 — chuyển kho

CK xuất/giao/nhận, máy đích chỉ định, projection theo store, kiểm đếm thiếu/dư/0, snapshot giá vốn và outbox causal. Toàn bộ 134 test Flutter và 108 test API đạt; analyze/lint/typecheck/dry-run và D1 local migration 20 đạt. Smoke HTTP workerd hai chi nhánh đạt luồng chuyển kho/nhận thiếu/replay/scope projection. Xem transfers.md. Source 0.5.0+5, chưa đóng gói lại; preview 0.4.0 vẫn schema 18. Chưa có payroll/dashboard/Web quản lý hoàn chỉnh hoặc backup cloud.

## Mốc source schema 21 — chấm công và bảo vệ phiên

Đã có chấm công append-only, phản hồi từ chối kỳ khóa khi sync, feed riêng theo quyền, che dữ liệu lương/bí mật trong audit, đóng màn riêng tư khi đổi quyền, thanh đồng bộ xuyên các route và hàng rào schema tương thích. Xem attendance-session.md cho kiểm chứng và giới hạn. Chưa phát hành bảng lương/phiếu lương; payroll-design.md vẫn là thiết kế cho các phần đó.

Toàn bộ 157 test Flutter / 125 test API đạt; Flutter analyze, API typecheck/lint/Worker dry-run và D1 local schema 21 đạt. Smoke HTTP workerd/database riêng đạt bootstrap/đăng nhập, quản trị/đăng ký/duyệt máy, CK hai cửa hàng với nhận thiếu/replay/projection, chấm công/replay/feed riêng và chặn client cũ. Không đo CPU production hoặc triển khai cloud. Lõi lương theo công/hoa hồng/thưởng có 7 test chung mỗi nền tảng; xem payroll-calculation.md, chưa có màn/bảng lương.

Build cuối Windows 0.5.0+5, Android APK 0.5.0/versionCode 5 và Web release đạt. EXE/version/schema 21 và APK chữ ký v2/quyền Internet/3 kiến trúc đã kiểm tra; APK ký debug. Web biên dịch được nhưng chưa có chức năng quản lý online hoàn chỉnh. Phạm vi đóng gói: preview-0.5.md; chưa nghiệm thu dữ liệu thật.

Đã đóng ZIP/APK preview 0.5.0: 45 file ZIP xác minh theo manifest hash/length; EXE và migration 21 khớp bản build/source, APK đủ 3 kiến trúc; SHA256 hai gói khớp sidecar. Preview 0.4.0 cũ vẫn schema 18 và không bị thay đổi. Không có server thử hoặc Gradle daemon được chủ động giữ chạy sau kiểm chứng.
