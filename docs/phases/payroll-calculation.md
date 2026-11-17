# Lõi tính lương — LEVEL 3, chưa phải phát hành bảng lương

Đã có CompensationRule và calculatePayroll ở Flutter/API, cùng bộ vector JSON trong docs/test-vectors/payroll.json. Một đơn vị công là nửa ngày; ngày chuẩn cấu hình 1–31, không tự tính làm thêm. Lương theo công = floor(lương cơ bản × min(công, công chuẩn) / công chuẩn). Hoa hồng = floor(max(doanh số thuần, 0) × basis points / 10000). Thưởng chỉ bậc cao nhất đạt ngưỡng, không cộng nhiều bậc. Số 0 phải cấu hình tường minh.

Mọi phép nhân/chia tiền dùng BigInt; đầu vào và tổng kết quả không vượt số nguyên an toàn dùng chung JSON/Dart/JS. Không chấp nhận số lẻ, chuỗi giả số, ngày chuẩn 0, bậc thưởng trùng/giảm/thừa trường. Không nhận thiếu cấu hình như một mức lương 0 mặc định.

7 test Flutter và 7 test API đạt: đủ công/đúng ngưỡng/không cộng dồn thưởng, nửa ngày và làm tròn, công vượt chuẩn/doanh số âm, nhân số lớn vượt khả năng integer của Number nhưng kết quả chính xác, lương 0 tường minh, input không hợp lệ và tổng tràn. Đã chạy trong toàn bộ 157 test Flutter / 125 test API; analyze/typecheck/lint/Worker dry-run đạt.

Chưa có cấu hình lương lưu/đồng bộ riêng tư, nguồn doanh số đối soát, chốt/hủy kỳ, bảng lương, phiếu lương PDF hoặc nút trả lương. Không thể sử dụng riêng calculator để tuyên bố đã chốt lương. Thiết kế các phần tiếp theo ở docs/architecture/payroll-design.md. Không bổ sung thuế, bảo hiểm hoặc giao dịch ngân hàng ngoài phạm vi.

Đề xuất: không bổ sung ngoài phạm vi đã duyệt.
