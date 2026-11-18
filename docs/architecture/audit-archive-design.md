# Lưu trữ nhật ký cũ — LEVEL 3

Phạm vi còn lại trong yêu cầu đã duyệt: giữ nhật ký gần đây trong D1, log cũ nén ra kho riêng để giảm dung lượng, vẫn kiểm chứng chain và xử lý replay. Không xóa dữ liệu bán hàng hoặc thực thi compaction trên cloud thật trong phiên phát triển.

Thiết kế triển khai:

1. Chỉ chủ có quyền hiện tại và quyền lúc cấp phiên được chuẩn bị/lưu trữ. Đọc file theo quyền audit và phạm vi cửa hàng. Không có quyền compaction trong sync token hoặc payload client.
2. Mỗi lô là một đoạn đầu liên tục của một chain (store, device, phía client dương/API âm), sau checkpoint trước. Chỉ lấy log đã ở cloud quá thời gian giữ (mặc định 90 ngày), dùng server_time thay vì đồng hồ client. Không nhảy qua log mới để tạo lỗ chain. Lô có giới hạn số hàng và byte; không quét toàn bảng.
3. Manifest ghi ID lô client UUIDv7, phạm vi/range, hash trước/cuối, hash nội dung nguồn, số hàng, byte, cutoff và key R2 cố định. Nội dung nguồn là byte JSON canonical do server chuẩn bị. Client nén gzip các byte này, không dựng lại JSON theo thư viện khác.
4. Upload vào R2 private riêng/binding được cấu hình rõ. Worker chỉ xác minh giải nén có giới hạn, checksum và đọc lại object, không tạo PDF hoặc nén/tổng hợp lớn. Không đủ binding, lỗi quota, checksum hoặc readback: giữ nguyên log D1. API chỉ ghi verified khi object đọc lại đúng nguồn chuẩn bị. Không có URL public.
5. Commit dùng guard transaction: checkpoint chưa đổi, range và hash log vẫn khớp manifest verified. Ghi checkpoint/receipt tối thiểu trước khi bỏ bản log nóng và bản sao audit tương ứng trong change_feed. Thao tác delete chỉ được trigger cho phép khi có guard của lô verified; API nghiệp vụ vẫn append-only, không sửa log. Manifest và receipt bất biến, có audit compaction riêng.
6. Receipt nhỏ lưu ID/index/digest toàn bản ghi (kể cả metadata không thuộc chain hash), giúp retry log cũ qua envelope khác không chèn lại hoặc đổi nội dung đã lưu trữ. processed_mutations vẫn giữ để ACK đúng envelope cũ. Hash checkpoint dùng làm predecessor cho log mới; API negative chain tiếp tục giảm, không reset về -1.
7. Native giữ lịch sử local, không tự purge SQLite. Máy mới và màn cloud thấy thông tin kho lưu trữ, có tải file theo quyền để kiểm tra. Sau khôi phục cloud phải khôi phục cả checkpoint/receipt/manifest và bucket; runbook/drill kiểm tra chain xuyên ranh giới archive.

Tình huống bắt buộc test: mất R2/upload/readback/commit; gzip sai/bomb; source thay đổi; hai commit cạnh tranh; actor thiếu quyền/scope; replay cũ đúng/sai nội dung; chain mới dương/âm sau archive; cursor sync sau bỏ feed cũ; chain có log mới hoặc thiếu đoạn; backup/restore metadata và tải file.

Archive giảm phần chi tiết/bản sao feed trong D1; receipt, chứng từ và sổ kho vẫn tăng theo giao dịch. Không hứa lưu vô hạn trong Free. Giữ băng cảnh báo dung lượng và runbook nâng gói. Không dùng số ngày/byte để xóa bất kỳ object chưa có manifest đã kiểm chứng.

Ràng buộc runtime đã đối chiếu: Workers hỗ trợ DecompressionStream gzip theo [Web standards](https://developers.cloudflare.com/workers/runtime-apis/web-standards/). CPU Free vẫn cần đo trên tài khoản được phép; giới hạn byte/lô và retry không thay cho phép đo production.

Đã triển khai và kiểm chứng local ở schema 30; xem ../phases/audit-archive-cloud-restore.md và ../operations/audit-archives.md. Chưa compaction dữ liệu cloud thật.
