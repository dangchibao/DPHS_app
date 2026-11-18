# ERD logic

```text
stores 1--N devices
users 1--1 employees
users N--N stores via employee_store_assignments -- roles N--N permissions
products 1--N product_variants -- sizes/colors/units
products -- categories/school_levels/school_years
size_charts 1--N size_chart_rules
stores N--N variants via store_variant_settings
stores+variants -- stock_movements / stock_balances(cache) / stock_reservations
devices+variants -- device_stock_allocations
documents 1--N document_events
documents 1--1 invoices/purchase_orders/tailoring_orders/returns/stock_transfers
invoices 1--N invoice_lines(snapshot) 1--N invoice_component_snapshots
payments N--N documents via payment_allocations
customers 1--N receivable_entries
schools 1--N classes -- school_years
students N--N classes via enrollments
customers -- students/schools/dealers
price_lists 1--N price_list_items
combos 1--N combo_components
promotions 1--N promotion_rules
vouchers 1--N voucher_redemptions
documents 1--N applied_promotion_snapshots
tailoring_orders 1--N tailoring_items -- measurements/surcharges snapshots
surcharge_rules 1--N surcharge_rule_versions
returns -- original_invoice; returns 1--N return_lines
transfers -- source_store/destination_store; transfers 1--N lines/events/discrepancies
employees -- attendance/compensation_versions
payroll_periods 1--N payslips 1--N payslip_lines
daily_store/product/employee_summaries
audit_logs -- audit_chain_checkpoints
backup_runs -- archive_manifests
local: outbox, cursors, document_counters
cloud: change_feed(server_seq), sessions
```

Schema vật lý được thêm theo phase bằng migration có test. Mỗi bảng nghiệp vụ có store_id. Danh mục toàn hệ thống, tài khoản, cấu hình hệ thống là ngoại lệ. UNIQUE(store_id,code) cho documents. Index pull (store_id,server_seq); không OFFSET/full scan cho sync.

Mốc schema 10: schools(customer_id), school_classes(school_id, academic_year), students(class_id, customer_id, student_code). Liên kết và snapshot trường/lớp/học sinh trên documents.metadata_json; partial index (store_id, student_id/school_id trong JSON, issued_at). Khách trường/phụ huynh là customers có định danh ổn định. Bảng enrollments trong sơ đồ logic chưa triển khai; class_id hiện là lớp đang học, lịch sử mua giữ lớp/niên khóa tại lúc bán trong snapshot. Tất cả FK mới giữa các bảng nghiệp vụ kiểm tra cả store_id.

Mốc schema 11: combo_rules(id,store_id,name,price,items_json,active,updated_at,lww_key) và combo_versions(store_id,combo_id,version,...), revision append-only. items_json chứa product_id và quantity; biến thể/size/màu được chọn lúc bán. documents.metadata_json giữ combo_groups để API kiểm chứng revision và combo_snapshots để in lịch sử. Partial unique (store_id,held_cart_id) chặn phát hành trùng từ cùng đơn tạm. Không đổi product_id của biến thể đã có để bảo toàn tham chiếu lịch sử.

Mốc schema 12: local_audit_receipts(store_id,audit_id,received_at) lưu biên nhận của audit local mà không cập nhật audit_logs append-only. D1 dùng audit_logs.server_time; bảng biên nhận trên D1 để trống. Cursor audit dùng khóa local riêng audit:<store_id>; cloud đọc cùng index change_feed(store_id,server_seq), lọc từng trang giới hạn 100 event.

Mốc schema 13: commercial_rules(id,store_id,name,kind,config_json,active,updated_at,lww_key), commercial_versions(store_id,rule_id,version,...) append-only. kind là price_list/promotion. Bảng giá chứa map variant_id → giá VND; khuyến mãi chứa mức giảm/ngưỡng/voucher và cờ cho phép kết hợp. Điều kiện trường/nhóm khách/ngày nằm trong config. documents.metadata_json giữ tham chiếu revision, tên quy tắc và promotion_discount; customers.kind=dealer dùng chung ledger công nợ.

Mốc schema 14: tailoring_rules/tailoring_versions có cấu hình phụ thu cơ bản, bậc số đo và yêu cầu. MR dùng documents + invoice_lines; metadata.tailoring giữ 8 số đo mm/gram, quy tắc/revision, yêu cầu, hẹn trả, ghi chú và phụ thu. document_events ghi TAILOR_SEWING/READY/DELIVERED, unique theo (store_id,document_id,type), có trigger thứ tự. payments/receivable_entries dùng chung cho đặt cọc và thu nợ MR.

Mốc schema 15: return_lines(id,store_id,document_id,original_line_id,quantity,credit,base_returned), liên kết DT với dòng HD/DT được nhận lại. Trigger chặn tổng trả vượt và lệch số lượng trước. receivable_adjustments(id,store_id,customer_id,document_id,credit_document_id,amount,created_at) là cấn nợ âm gắn DT; view receivable_ledger hợp entries + adjustments. Guard thu/cấn kiểm tra số dư không âm. DT dùng invoice_lines cho hàng thay thế, payments receive/refund; original_id nối chuỗi. CANCELLED unique theo chứng từ, related_id là DT hủy; hóa đơn gốc bất biến.

Mốc schema 16: thay audit_server_feed bằng JSON tối đa 32 đối số mỗi hàm; giữ đủ null và 18 trường audit. Không thay dữ liệu nghiệp vụ.

Mốc schema 17: reservation_lines(id,store_id,device_id,document_id,variant_id,quantity,expires_at,created_at) nối DH với lượng giữ; reservation_events(id,store_id,device_id,document_id,kind,related_document_id,user_id,reason,created_at) kết thúc DH bằng release/consume, unique(store_id,document_id). related_document_id là HD giao đủ hàng; metadata HD chứa reservation_id. Tồn khả dụng suy từ quyền máy trừ giữ còn hạn; stock_guard bảo vệ cả phần đang giữ. Không thêm ledger kho khi tạo, giải phóng hoặc hết hạn DH.

Mốc schema 18: device_enrollments(id,store_id,device_id,token_hash,created_at,expires_at), private không đồng bộ tới client. Index nghiệp vụ (store_id,expires_at), unique(store_id,device_id); index hash toàn cục dùng tra mã đăng ký trước khi biết store, tương tự auth token. Trigger không cho thay ID/store/code/created_at của device hoặc installation_hash đã gắn; revoked không được mở lại. Dữ liệu cũ không đổi. Danh tính/endpoint bản cài đã đăng ký lưu local_settings, không nhận từ sync payload.

Mốc schema 19: size_rules(id,store_id,product_id nullable,name,config_json,active,updated_at,lww_key). config_json là các dòng size với height_min/max theo mm và weight_min/max theo gram. Index(store_id,active,product_id), LWW cho cấu hình và guard không chuyển store. Không lưu số đo cá nhân nhập để gợi ý, không thay giá/tồn.

Mốc schema 20: transfer_events(id,store_id,device_id,document_id,user_id,reason,created_at) là dispatch unique theo CK xuất; transfer_receipts(id=CK nhận,store_id,device_id,offer_id,user_id,counts_json,reason,created_at), unique(store_id,offer_id). transfer_offers là projection tại store/máy đích, chứa source ids/codes, ngày, năm học, items_json/notes; transfer_deliveries là projection tại nguồn chứa biên nhận/counts/người nhận/chênh lệch. Cả bốn append-only, index bắt đầu store_id; chỉ event/receipt được client push. Guard stock chuyển yêu cầu CK cùng store/device/actor/time, đúng chiều, receipt trước stock nhập. CK có total=0, không doanh thu.

Mốc schema 21: attendance_entries append-only (store/device/operator/employee/work_day/day_units/reason/created/lww); attendance_rejections giữ hash/lý do server từ chối; local_attendance_receipts xác nhận event canonical. payroll_locks(store,employee,run,period_start,period_end) và payroll_lock_releases(store,run,time) là projection không chứa số lương. Feed attendance có cursor riêng; generic feed không công khai dữ liệu chấm công cho thu ngân/kho. Index nghiệp vụ bắt đầu store_id.

Mốc schema 22: compensation_versions revision/CAS; payroll_commands local intent + payroll_results accepted/rejected immutable; payroll_runs snapshots, payroll_voids, payroll_reconciliations; payroll_feed(store_id,server_seq) riêng; sync_checkpoints mỗi máy/ngày và payroll_guards kiểm watermark nguyên tử. payroll_sales_source hợp HD/MR + dòng thay DT - credit trả theo nhân viên bán gốc. Các bảng lương không trong generic sync allowlist; chỉ public locks/releases đi feed attendance.

Schema 23–25: private_access_marks(store,session,kind) ghi lần đọc lương; payments index ngày. daily_reports(store,day,year,school), report_receipts(store,document), report_cache_state(store), receivable_report_balances(store,document) là projection cloud, không đi generic feed. devices.kind native/web bất biến; browser không có stock allocation/checkpoint/sync grants. Schema 26 thêm bank_accounts(id=store_id,device,user,config_json,updated_at,lww_key), cấu hình một tài khoản/QR mỗi cửa hàng, LWW có audit/outbox; ledger và quyền không dùng LWW.


Schema 27: media_objects(id=SHA256, mime, bytes, created_at) metadata ảnh dùng chung; media_cache BLOB có checksum; media_outbox(store,device,user,hash,attempts,next_attempt_at) riêng ảnh. Cache và file ảnh không phải ledger. Schema 28: staff_change_requests(store,user,device,scope,payload,snapshot,status) + staff_change_devices(store,request,device,acked_at,cursor) và staff_change_guards CAS; không dùng LWW cho quyền.

Schema 29: stock_threshold_rules(id,store,device,user,variant,threshold,version_key,created_at) append-only; trigger chiếu phiên bản mới nhất vào store_variant_settings.low_stock_threshold, giữ price_override. Index(store,variant,version_key); audit thêm index(store,client_time,id) để đọc keyset có giới hạn.

Schema 30: audit_archives(store,device,direction,range,source/gzip hashes,status,object_key) có manifest bất biến; audit_chain_checkpoints(store,device,direction,upto,index,hash) và audit_archive_receipts(store,device,id,index,digest) append-only. audit_archive_guards cho phép compaction đúng lô verified; endpoint thường không được xóa audit. Partial index change_feed(store,entity_id) chỉ audit và bỏ audit_store_time dư thừa. Native giữ head cloud trong local_settings theo chính store/device; không tự purge local audit.
