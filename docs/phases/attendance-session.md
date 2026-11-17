# Chấm công và ranh giới phiên — LEVEL 3, schema 21

Chủ/quản lý/kế toán chấm công 0 / 0,5 / 1 ngày theo nhân viên, tháng và ngày Việt Nam, bắt buộc lý do. Sửa công tạo sự kiện mới; lịch sử không bị xóa. Không chấm ngày tương lai. Mỗi thao tác ghi event/audit/outbox cùng transaction SQLite. Màn hình phân biệt công đang chờ với công server đã xác nhận.

API kiểm tra current + issued role, nhân viên cùng cửa hàng, thời gian và dữ liệu. Feed chấm công có scope/cursor riêng, thu ngân/kho không đọc được. Nếu kỳ bị khóa trước lúc nhận event offline, server lưu bản từ chối có hash rồi ACK; app giữ lịch sử nhưng loại event bị từ chối khỏi số công. Replay không nhân đôi hoặc đổi nội dung. payroll_locks/releases đã có để bảo vệ kỳ, nhưng nghiệp vụ phát hành/hủy bảng lương chưa triển khai trong mốc này.

Audit che khóa bí mật và số lương/cấu hình lương trước khi băm. API từ chối audit client chưa che thay vì sửa chain. Thay đổi vai trò/khóa tài khoản nhận từ cloud làm hết phiên hiện tại; lỗi 401 của phiên tương tác xóa lease bền vững. Ranh giới phiên đóng các màn riêng tư đang mở. Hàng đợi giao dịch vẫn được giữ. Thu hồi khi máy mất mạng vẫn chịu giới hạn lease offline; không cam kết thu hồi tức thì khi offline.

Thanh đồng bộ nằm ngoài Navigator, luôn hiện cả khi mở trang con và đăng nhập. Đăng ký máy thành công đóng SQLite trước khi tạo provider mới để tránh khóa file.

App gửi X-Client-Schema. Worker yêu cầu schema tối thiểu 21 trước directory/push/pull để bản cũ không áp dụng loại feed chưa biết. Header không thay xác thực/quyền. Nâng schema reset cursor để replay idempotent, giữ nguyên chứng từ, công nợ, kho, counter và outbox. Cần cập nhật app/API đồng bộ phiên bản. MR chốt thời điểm trong transaction và kiểm lại ngày hẹn sau khi chờ khóa qua nửa đêm; chấm công lấy ngày Việt Nam từ chính timestamp sự kiện.

Kiểm chứng tích hợp: toàn bộ 157 test Flutter / 125 test API, analyze/typecheck/lint/Worker dry-run và D1 local migration 21 đạt. Có regression upgrade giữ dữ liệu/reset cursor, server từ chối client cũ, thu hồi lease bền vững, MR chờ transaction qua nửa đêm. Trong tổng số này có 7 test tính lương ở mỗi nền tảng; đó mới là lõi công thức, không phải nghiệp vụ phát hành bảng lương.

Smoke HTTP workerd/database riêng đạt schema 21, đăng nhập, quản trị máy/chi nhánh, CK hai cửa hàng, chấm công/replay/feed riêng và chặn client cũ; không phải số đo CPU production.

Chạy thử: ./scripts/dev.ps1 → đăng nhập chủ/quản lý/kế toán → Chấm công; chỉnh ngày/công/lý do, xem trạng thái chờ và đồng bộ. Dùng dữ liệu thử. Source 0.5.0+5/schema 21; trạng thái đóng gói xem progress.md. ZIP/APK 0.4.0 vẫn schema 18. Chưa có bảng lương/phiếu lương, dashboard/Web quản lý hoàn chỉnh hoặc backup cloud. Không deploy production.

Đề xuất: không bổ sung ngoài phạm vi đã duyệt.
