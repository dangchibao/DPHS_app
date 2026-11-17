# Phase 0 — hoàn thành nền tảng

15/11/2026: đã tạo monorepo Flutter Windows/Android/Web, Workers/D1 local, CI test/lint/build, README/AGENTS/CLAUDE, ERD và quyết định kiến trúc. UI shell tiếng Việt xanh–trắng–xám, placeholder 5 nhóm đồ.

Đã chạy thành công: Flutter analyze; widget test; flutter build windows --release (EXE); API tsc; 2 Vitest tests; D1 migration local; Worker dry-run build. Chưa triển khai cloud, chưa push. CI đã viết nhưng chưa chạy trên GitHub.

Chạy: .\scripts\dev.ps1. Bản build: app/build/windows/x64/runner/Release/ngoc_thanh_pos.exe (cần thư mục DLL/data cùng đi kèm).

Đề xuất: không có tính năng ngoài phạm vi.
