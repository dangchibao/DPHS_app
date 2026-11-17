# Chạy thử bản đang phát triển

## Windows

Mở PowerShell tại `D:\app\DPHS_app`, chạy:

```powershell
.\scripts\dev.ps1
```

Script đọc cấu hình `.env`, mở API local và ứng dụng. Tài khoản là `admin`, mật khẩu dùng giá trị đã đặt trong `.env`. Không đưa `.env` lên GitHub. Đóng cửa sổ EXE đã mở trước khi chạy lệnh để tránh hai tiến trình cùng mở database.

Khi chạy EXE trực tiếp lần đầu và chưa có cấu hình môi trường, màn hình yêu cầu khởi tạo mật khẩu quản trị tối thiểu 10 ký tự. Bộ portable cần giữ EXE cùng tất cả DLL và thư mục `data`; không sao chép riêng EXE. Dữ liệu SQLite lưu trong thư mục hỗ trợ ứng dụng của Windows, không nằm trong thư mục build.

## Các luồng có thể thử

1. **Sản phẩm:** thêm sản phẩm, nhập size/màu/SKU/mã vạch, giá vốn/giá bán; chỉnh sửa hoặc thêm biến thể trong menu của thẻ hàng. Ngừng bán vẫn giữ lịch sử.
2. **Kho:** nhập số dương hoặc điều chỉnh số âm, bắt buộc ghi lý do. Không được vượt tồn hoặc phân bổ bán của máy. Lịch sử ghi qua sổ cái.
3. **POS:** tìm tên hoặc quét HID vào ô tìm kiếm, Enter để thêm; chọn hàng, đổi số lượng, giảm giá, thanh toán. F2 tìm kiếm, F4 giữ đơn, F9 thanh toán. Kiểm tra tên phím trên màn hình trước thao tác.
4. **Đặt cọc:** nhập tên/điện thoại khách và số tiền thực thu thấp hơn tổng. Phần còn lại thành công nợ.
5. **Thu công nợ:** mở menu góc phải → Đặt cọc & công nợ. Chọn thu tiền, phương thức và nội dung. Có thể thu nhiều lần, không vượt số nợ; hiện dùng máy đã lập hóa đơn. Lịch sử vẫn có các lần thu ban đầu và thu tiếp.
6. **Hóa đơn:** mở danh sách hóa đơn, xem/lưu PDF; chủ/quản lý có nút lịch sử thao tác. Bản PDF hóa đơn giữ thông tin lúc phát hành, không sửa dữ liệu gốc.
7. **Tem mã vạch:** menu → Xuất tem mã vạch PDF; chọn biến thể đã có mã, khổ tem và số bản, xem trước rồi lưu. Chưa có kết nối máy in trực tiếp.
8. **Nhân viên:** chủ/quản lý tạo tài khoản, đổi vai trò hoặc khóa nhân viên, bắt buộc lý do. Thao tác quản trị quyền cần API online; thu ngân không có quyền này. Không xóa lịch sử nhân viên đã có giao dịch.
9. **Sao lưu:** menu → Sao lưu & khôi phục, chọn thư mục/lịch/số bản giữ lại. Có thể bật mã hóa bằng mật khẩu riêng. Giữ mật khẩu ở nơi an toàn vì không có cơ chế khôi phục mật khẩu backup.
10. **Nhật ký:** chủ/quản lý lọc theo người, máy, chứng từ, hành động, thời gian; xuất Excel/PDF.

11. **Trường/lớp/học sinh:** menu tương ứng để thêm/sửa danh mục; tại thanh toán POS chọn học sinh hoặc đơn tập thể. Hóa đơn/PDF giữ tên trường/lớp/học sinh tại thời điểm mua.
12. **Combo:** menu → Combo đồng phục để cấu hình giá bộ và thành phần; POS chọn combo, chọn size/màu từng món, thêm hàng lẻ nếu cần. Giữ đơn tạm lưu cả lựa chọn combo.

13. **Giá riêng/khuyến mãi/đại lý:** menu tương ứng để cấu hình. Tại thanh toán POS chọn bảng giá, chương trình và voucher; sai điều kiện chặn hoàn tất, mặc định không cộng dồn.
14. **May riêng:** menu → Đơn may riêng; cấu hình bảng phụ thu rồi nhận đơn đủ số đo, hẹn trả và đặt cọc. Chuyển từng bước tiến độ; phiếu đo PDF A4. Thu thêm tiền qua công nợ.
15. **Đổi size/đổi trả:** chọn hóa đơn gốc còn hàng, số lượng/lý do và hàng thay thế. Đổi size cùng sản phẩm có thể giữ giá sau ưu đãi. Kiểm tra cấn nợ/thu thêm/hoàn tiền rồi xác nhận; xem PDF trong lịch sử DT. Chủ/quản lý có nút hủy HD riêng.

## Kiểm thử mất mạng và khôi phục

Source/bản thử 0.5.0 bổ sung: **Bảng size** để cấu hình khoảng chiều cao/cân nặng và gợi ý; **Chuyển kho cửa hàng** để xuất CK, xác nhận giao và kiểm đếm tại máy nhận chỉ định; **Chấm công nhân viên** cho chủ/quản lý/kế toán. Chấm công yêu cầu lý do, sửa bằng bản ghi mới và hiển thị trạng thái chờ server. Chưa có chức năng phát hành bảng lương.

Đăng nhập online trước để có quyền offline còn hạn; tắt API local rồi thử bán. Hàng đợi phải tăng, giỏ và tồn cập nhật ngay. Mở lại API, bấm đồng bộ và kiểm tra hàng đợi hết; gửi lại không nhân đôi hóa đơn.

Chỉ diễn tập restore trên dữ liệu thử. Restore có xác nhận hai lần và lý do; ứng dụng tự sao lưu hiện trạng và giữ hàng đợi. Sau restore phải đăng nhập/kết nối cloud để đối soát hết và nâng counter rồi mới bán tiếp. Thiết bị khác danh tính không được nhận một bản sao database để dùng chung mã máy.

## Giới hạn bản này

Chưa nghiệm thu toàn bộ phần mềm. QR chuyển khoản còn là vùng chờ cấu hình, không xác minh giao dịch ngân hàng. Đã có giữ hàng có hạn và đăng ký/duyệt máy, tạo chi nhánh ở bản 0.4.0/schema 18. Chuyển kho, bàn giao nhân viên/quyền tồn, payroll/dashboard và Web quản lý còn chưa hoàn chỉnh. Khởi tạo dữ liệu mẫu chỉ dành thử local; thiết bị thực tế phải đăng ký danh tính riêng với API đã provision. Xem `docs/phases/progress.md`.

## Giữ hàng và thiết bị mới (0.4.0)

Menu **Giữ hàng · đặt trước**: tạo DH với tên/điện thoại, thời hạn giờ và số lượng. DH giảm tồn khả dụng, chưa xuất kho/chưa thu tiền. Giao hàng mở POS, phải đủ các món giữ và còn hạn; giá được xác nhận lại. Giải phóng cần lý do và thao tác trên máy lập DH.

Chủ đăng nhập online → **Cửa hàng · thiết bị** để thêm chi nhánh, mời máy và gán nhân viên đã có vào chi nhánh mới. Trên bản cài trống chọn **Kết nối chi nhánh · đăng ký máy mới**, nhập API HTTPS và mã đăng ký trong 1 giờ. Chủ tải lại danh sách rồi duyệt; nhân viên đăng nhập online lần đầu. Không sao chép database để tạo máy bán thứ hai. Thu hồi máy không thể thông báo tức thì khi máy đang mất mạng; đồng bộ hết giao dịch trước khi thu hồi.

APK thử nghiệm hiện sử dụng khóa ký debug của công cụ build. Bản phát hành cuối cần khóa ký do chủ ứng dụng quản lý. Chưa có cloud production hoặc dịch vụ trả phí được kích hoạt.
