# Lương và phiếu lương — LEVEL 3, schema 22

Đã triển khai cấu hình lương theo nhân viên/cửa hàng/tháng áp dụng, lịch sử revision bất biến và CAS chống hai máy ghi đè. Lương theo công, hoa hồng phần trăm và một bậc thưởng cao nhất dùng số nguyên BigInt; không tự tính thuế/bảo hiểm/làm thêm hoặc chuyển tiền ngân hàng. Không có cấu hình thì không coi lương bằng 0.

Menu **Lương · phiếu lương** chỉ chủ/kế toán. Có thể lập yêu cầu cấu hình offline; audit che dữ liệu và outbox cùng transaction. Yêu cầu lương đi /payroll/push riêng theo người tạo, mỗi request một command. ACK không trả số lương. Kết quả accepted/rejected bất biến, replay cùng ID/hash không nhân đôi; dữ liệu khác dùng lại ID bị từ chối. Bản từ chối hiện trong giao diện, không âm thầm bỏ và không chặn hàng đợi POS vô hạn.

Nguồn đối soát trên D1: HD/MR + giá sau giảm của món thay DT − credit của hàng trả. Khoản trả ghi giảm nhân viên bán dòng gốc theo ngày phiếu DT; không dùng DT.total, không tính DH/CK. Chấm công lấy event mới nhất mỗi ngày, loại event bị server từ chối. Nguồn/nhân viên/cấu hình/tổng tiền giữ snapshot trong phiếu.

Chốt phải online, sau kết thúc tháng, gửi hết outbox máy hiện tại và có checkpoint sau kỳ của các máy đã được duyệt/tồn tại trong kỳ. App gửi checkpoint tối đa một lần/ngày/máy sau khi đẩy/kéo xong; cursor server kiểm tra lại trong transaction. Chủ/kế toán xác nhận đã đối soát cả máy đã thu hồi. Không giả định checkpoint chứng minh được mọi dữ liệu chưa nhìn thấy: giao dịch phát sinh muộn hoặc đồng hồ quay lùi làm ảnh hưởng kỳ đã chốt sẽ tạo payroll_reconciliations, cảnh báo trong UI/PDF. Phiếu cũ không tự thay đổi; xử lý bằng hủy/phát hành lại.

Preview hash và business/private watermark được kiểm tra trước/sau đọc nguồn và trong transaction chốt. Nguồn/cấu hình đổi giữa lúc xem và ghi thì không phát hành phiếu. Chốt tạo payroll_locks công khai chỉ chứa IDs/kỳ, khóa sửa công; hủy tạo payroll_voids và payroll_lock_releases, không xóa lịch sử. Máy offline gửi công tới sau khóa nhận rejection/ACK rõ ràng.

Số lương dùng payroll_feed riêng (store_id,server_seq), chỉ phiên tương tác chủ/kế toán đọc; manager/thu ngân/kho và token sync nền không đọc được. Native dùng cursor payroll:<store_id>, từ chối dữ liệu lương trong kênh bán hàng. Backup/restore giữ intent/outbox và reset cursor riêng khi đối soát. Bảo vệ quyền ở service/API; không tuyên bố chống người có toàn quyền hệ điều hành trên file SQLite/backup.

Có bảng lương theo tháng toàn cửa hàng, tổng phiếu đang hiệu lực bằng BigInt, lịch sử từng người và PDF A5 tiếng Việt. Phiếu hủy/cần đối soát có cảnh báo; PDF không xác nhận đã chi trả. Đã tạo mẫu QA và render Poppler, kiểm tra trực quan một trang A5 không tràn.

Kiểm chứng hiện tại: 129 test API đạt, typecheck/lint/Worker dry-run và D1 local migration 22 đạt. 165 test Flutter toàn bộ đạt trước bổ sung bảng tổng tháng; nhóm payroll service/sync/UI/PDF đã đạt, kiểm tra toàn bộ sau bổ sung đang chạy. Smoke HTTP workerd/database riêng đạt cấu hình/preview/chốt/replay/feed riêng/khóa công/rejection/hủy/phát hành lại, cùng các luồng cũ đăng nhập/thiết bị/CK. Không deploy cloud. Số kiểm thử cuối cập nhật sau khi chạy thành công.

Source 0.6.0+6/schema 22 chưa đóng gói; ZIP/APK 0.5.0 vẫn schema 21, chưa có module lương. API source yêu cầu schema tối thiểu 22. Chạy ./scripts/dev.ps1, đăng nhập chủ/kế toán → Lương · phiếu lương; cấu hình, đồng bộ, đối soát tháng và xem phiếu. Chỉ dùng dữ liệu thử.

Đề xuất: không bổ sung ngoài phạm vi; còn tích hợp Web online và báo cáo toàn hệ thống ở phase tiếp theo.
