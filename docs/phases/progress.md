# Tiến độ kiểm chứng — cập nhật 17/11/2026

Người dùng đã cho phép tiếp tục tự động giữa các phase. Đây là mốc tích hợp đang phát triển, chưa phải nghiệm thu toàn bộ yêu cầu và chưa dùng cho dữ liệu thật.

## Trạng thái hiện tại — 0.7.0+7/schema 30

Các nhóm nghiệp vụ trong yêu cầu đã có trong source và bản chạy thử: POS, kho/biến thể/size/barcode, PDF, combo, trường/lớp/học sinh, khuyến mãi/giá riêng, may riêng, đổi trả, cọc/công nợ, giữ hàng, chuyển kho, nhân viên/quyền/chấm công/lương, dashboard/báo cáo, đồng bộ, audit và sao lưu/khôi phục. Windows có bộ cài EXE và bản portable kèm CRT; Android có cả APK debug preview và APK ký release bằng khóa ngoài repo; Web/PWA staging online đã deploy.

Cloudflare staging đã hoạt động, khóa Android release đã tạo và cần chủ sao lưu độc lập. Những việc còn lại để đưa vào vận hành là kích hoạt R2 có kiểm soát chi phí, thiết lập GitHub backup/secrets, nghiệm thu tải và thiết bị vật lý. Không tự push/deploy/thay production/bật phí theo AGENTS.md. Chưa có cơ sở cam kết hạn mức miễn phí đủ cho mọi tải hoặc nghiệm thu máy thật. Xem remaining-requested.md, preview-0.7.md và windows-installer.md để biết phạm vi hiện hành.

## Cách đọc các mốc bên dưới

Các phần bên dưới giữ lịch sử kiểm chứng từ các schema trước. Câu “chưa hoàn thiện” tại một mốc không phải danh sách tính năng còn thiếu của source hiện tại; mốc mới hơn ở cuối tài liệu thay thế trạng thái cũ. Đặc biệt, lương/Web/bàn giao/audit archive đã được bổ sung sau các bản 0.2–0.5. Không dùng số test của mốc cũ để mô tả lần chạy mới.

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

## Các việc còn lại tại mốc cũ (lịch sử)

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

## Mốc source schema 22 — lương và phiếu lương

Cấu hình CAS, private outbox/feed, đối soát/checkpoint ngày, chốt/hủy/phát hành lại, khóa công, cờ giao dịch tới muộn, bảng lương toàn cửa hàng theo tháng và PDF A5 đã có. 166 test Flutter / 129 test API, analyze/typecheck/lint/Worker dry-run, D1 local migration 22 và build Windows release 0.6.0+6 đạt. Smoke HTTP workerd toàn luồng lương đạt; PDF đã kiểm tra trực quan một trang. Xem payroll.md. Chưa đóng gói source 0.6.0; ZIP/APK 0.5.0 vẫn schema 21. Không deploy cloud.

## Mốc source schema 24–25 — báo cáo cloud và Web online

Xem reports-cloud-web.md: 181 Flutter / 140 API đạt, build Windows/Web schema 25, workerd HTTP và Chrome release đăng ký/đăng nhập/dashboard/thu hồi phiên đạt. Hạn chế bộ test Chrome iframe được ghi rõ. Preview 0.5.0 vẫn schema 21. Pipeline backup cloud chuẩn bị, 7 test Python gồm GPG thực và restore SQL Wrangler local đạt; chưa chạy cloud/GitHub thật. Source hiện đã sang schema 26 cho QR chuyển khoản, đang kiểm chứng; chưa đóng gói lại.


## Mốc schema 27–28 — ảnh, QR, hạn mức và bàn giao

Schema 27: ảnh sản phẩm nén/cache SQLite, R2 tùy chọn, tài khoản/QR chuyển khoản, bảng cảnh báo hạn mức cloud. Windows/Web build schema 27 đạt; Worker HTTP D1/R2 local đạt. Schema 28: bàn giao quyền chờ máy drain queue, frozen interactive, current/issued RBAC, chốt nguyên tử và thu hồi grant. Toàn bộ 195 test Flutter/155 test API, analyze/typecheck/lint và 10 test backup Python đạt. HTTP workerd schema 28 đạt, gồm hóa đơn cũ gửi trong khi bàn giao và hai ACK thiết bị. Xem media-bank-usage.md và staff-handoff.md. Source schema 29 đang tích hợp; chưa đóng gói bản 0.6.0. Chưa chạy cloud thật.

## Preview 0.6.0+6 — schema 29

201 test Flutter, 163 test API và 10 test backup Python đạt; analyze/typecheck/lint/Worker dry-run đạt. Ngắt tiến trình thật trước/sau commit SQLite xác nhận mã 001/002, replay, kho, audit và outbox. Windows/Web/APK release build đạt; APK versionCode 6, v2, Internet và ba ABI đạt. Chrome release đã kiểm chứng enrollment/login/dashboard/catalog/lương online/audit desktop/mobile/revoke, không JS exception. Xem preview-0.6.md và store-settings-web-management.md. Source tiếp tục kho lưu trữ audit; không coi bản chạy thử là nghiệm thu hoàn tất hoặc cloud production.

## Source 0.7.0+7 — schema 30

Archive audit có file private/checkpoint/receipt/guard và tiếp tục chain/replay; importer cloud phục hồi bind dữ liệu lớn chỉ staging. Toàn bộ 204 test Flutter, 169 test API, 19 test Python đạt; workerd D1/R2 và Chrome release desktop/mobile/private-route revoke đạt. Windows/Web/APK 0.7 build cuối đạt. Windows ZIP 66 file/Web ZIP 75 file manifest khớp checksum; APK schema 30/versionCode 7/v2/Internet/ba ABI đạt. Process kill schema 30 đã kiểm chứng trọn lượt. Xem audit-archive-cloud-restore.md và preview-0.7.md. Còn setup/nghiệm thu cloud, GitHub, khóa ký và máy thật; không tự deploy/push/kích hoạt phí.

Bổ sung bộ cài Windows per-user và CRT app-local: đã kiểm thử lifecycle cài/sửa/nâng/hạ/chặn khóa/gỡ giữ dữ liệu fixture. ZIP có 66 tệp manifest. Xem windows-installer.md; chưa ký Authenticode hoặc nghiệm thu Windows sạch.

Lượt kiểm chứng hai file SQLite độc lập: 205 test Flutter đạt, analyze sạch; mất ACK/khởi động lại/replay/không vượt phân bổ đều đạt. Xem two-device-recovery.md. Chỉ đổi test/tài liệu; gói 0.7.0 không thay mã sản phẩm. Nghiệm thu phần cứng/cloud vẫn cần môi trường thật.

Kiểm tra môi trường phát hành 17/11: Git remote đọc được, Wrangler báo chưa xác thực, cấu hình production local và bộ biến ký Android chưa có; adb trống. Xem ../operations/environment-status.md để biết thao tác đăng nhập cần chủ tài khoản thực hiện. Chỉ đọc, không deploy/push; không chạy lại test vì không đổi mã.

Cập nhật sau đăng nhập Cloudflare: staging Web/Workers/D1 APAC schema 30 đã deploy, owner provision kiểm soát, 14 HTTP checks thực và restore D1→D1 84 bảng đạt; APK release mới ký bằng khóa ngoài repo đã build/verify. API 176 test đạt. Xem cloud-staging-release.md và ../operations/staging-access.md. R2 trả 10042/chưa bật, GitHub backup chưa kích hoạt, còn nghiệm thu thiết bị và sao lưu khóa do chủ giữ.

Ngày 18/11 chốt hồ sơ Native→Cloudflare E2E: 2 hóa đơn/2 mã, 3 payments/700.000đ, ledger/cache 7, nợ 0, QA sessions 0 và endpoint QA tắt. Khóa GPG ngoài repo đã chuẩn bị, diễn tập private-export→keyring mới→giải mã/restore đạt; 23 test Python đạt. Xem native-cloud-e2e-backup-key.md. R2 còn 10042, workflow chưa có trên main public và chưa push theo AGENTS; sao lưu định kỳ chưa hoạt động.

Hotfix Web 18/11 đã deploy: lưu/tự điền cặp ID sau đăng nhập trực tiếp, tương thích khóa cũ, không lưu token/mật khẩu/quyền; bỏ phản hồi login muộn khi đóng màn hình. 209 test Flutter/analyze đạt, Web build và Chrome/HTTPS đạt. Xem web-login-identity.md. Không migration/schema/native/API; R2/GitHub backup vẫn cần các điều kiện ngoài môi trường đã ghi.

Ngày 18/11 rà soát lại readiness: remaining-requested.md là backlog hiện hành, các ghi chú schema cũ là lịch sử. R2 còn activation-required/10042 và workflow backup trên main còn 404. Không đổi code, không có lượt test/build/deploy mới trong lần cập nhật này.
