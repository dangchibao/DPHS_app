# Thư viện Visual C++ trong bản Windows

Windows x64 cần Visual C++ runtime, kể cả máy không có Visual Studio. Gói Windows thêm CRT app-local từ thư mục redistributable của đúng Visual Studio đã build ứng dụng. Không lấy DLL từ System32, thư mục debug hoặc Internet không xác định. Mỗi DLL được kiểm tra PE x64 và chữ ký Microsoft; visual-cpp-runtime.json ghi phiên bản và SHA-256. Các DLL này chỉ được chép cạnh EXE, không thay thế thư viện hệ thống.

Điều kiện phân phối phụ thuộc giấy phép Visual Studio của đơn vị phát hành. Xem [Microsoft: Redistribute Visual C++ files](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170) và [danh mục giấy phép Visual Studio](https://visualstudio.microsoft.com/license-terms/). Bản chạy thử hiện được build bằng Visual Studio Community có trên máy phát triển. Người phát hành cần kiểm tra điều kiện giấy phép áp dụng cho tổ chức mình.

Script package-preview.ps1 tự tìm CRT x64 trong VC/Redist/MSVC của Visual Studio ghi ở CMakeCache.txt. Có thể đặt WINDOWS_VC_REDIST_DIR tới thư mục Microsoft.VC*.CRT x64 redistributable tương ứng. Thiếu DLL/chữ ký sai/sai kiến trúc sẽ dừng đóng gói.

Đóng gói app-local không kiểm chứng thay cho chạy trên Windows sạch và không tự cập nhật runtime trong các gói đã phát hành. Khi cập nhật runtime, build/đóng gói và nghiệm thu lại. Không đổi thư mục dữ liệu ứng dụng; gỡ cài đặt giữ nguyên SQLite, hàng đợi và backup.
