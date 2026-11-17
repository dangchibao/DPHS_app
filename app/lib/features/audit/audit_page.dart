import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../../core/export/report_export.dart';

const actionLabels = {
  'COMBO_SAVE': 'Cập nhật giá / thành phần combo',
  'COMMERCIAL_SAVE': 'Cập nhật bảng giá / khuyến mãi',
  'DEALER_SAVE': 'Cập nhật đại lý',
  'TAILOR_RULE_SAVE': 'Cập nhật phụ thu may',
  'TAILOR_CREATE': 'Nhận đơn may riêng',
  'TAILOR_STATUS': 'Cập nhật tiến độ may',
  'TAILOR_SYNC': 'Tiếp nhận phiếu may offline',
  'RETURN_CREATE': 'Tạo phiếu đổi/trả',
  'RETURN_SYNC': 'Tiếp nhận phiếu đổi/trả offline',
  'INVOICE_VOID': 'Hủy hóa đơn bằng phiếu mới',
  'SCHOOL_SAVE': 'Cập nhật trường',
  'CLASS_SAVE': 'Cập nhật lớp / niên khóa',
  'STUDENT_SAVE': 'Cập nhật học sinh / phụ huynh',
  'SCHOOL_SEED': 'Khởi tạo trường / lớp / học sinh mẫu',
  'LOGIN_SUCCESS': 'Đăng nhập thành công',
  'LOGIN_FAILED': 'Đăng nhập thất bại',
  'LOGOUT': 'Đăng xuất',
  'PASSWORD_CHANGE': 'Đổi mật khẩu',
  'STAFF_CREATE': 'Tạo nhân viên',
  'STAFF_UPDATE': 'Đổi quyền / hồ sơ nhân viên',
  'INVOICE_CREATE': 'Tạo hóa đơn',
  'INVOICE_CANCEL': 'Hủy hóa đơn',
  'INVOICE_SYNC': 'Tiếp nhận hóa đơn',
  'PAYMENT_RECEIVE': 'Thu tiền',
  'PAYMENT_REFUND': 'Hoàn tiền',
  'DISCOUNT_OVERRIDE': 'Giảm giá vượt ngưỡng',
  'PRODUCT_CREATE': 'Thêm sản phẩm',
  'PRODUCT_UPDATE': 'Sửa sản phẩm / giá',
  'PRODUCT_ARCHIVE': 'Ngừng bán biến thể',
  'STOCK_ADJUST': 'Điều chỉnh tồn kho',
  'STOCK_REBUILD': 'Đối chiếu sổ kho',
  'TRANSFER_CREATE': 'Xuất chuyển kho',
  'TRANSFER_RECEIVE': 'Nhận chuyển kho',
  'BACKUP_SUCCESS': 'Sao lưu thành công',
  'BACKUP_VERIFY': 'Kiểm tra bản sao lưu',
  'BACKUP_ROTATE': 'Xoay vòng sao lưu',
  'RESTORE_APPLY': 'Khôi phục dữ liệu',
  'RESTORE_RECONCILED': 'Đối soát sau khôi phục',
  'CONFIG_UPDATE': 'Đổi cấu hình',
  'DATA_EXPORT': 'Xuất dữ liệu',
  'SYSTEM_BOOTSTRAP': 'Khởi tạo hệ thống',
  'CART_HOLD': 'Giữ đơn tạm',
};
const severityLabels = {
  'normal': 'Bình thường',
  'sensitive': 'Nhạy cảm',
  'critical': 'Nghiêm trọng',
};

class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.service, this.entityId});
  final LocalService service;
  final String? entityId;
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final search = TextEditingController(),
      user = TextEditingController(),
      device = TextEditingController();
  String action = '', severity = '';
  List<Map<String, Object?>> rows = [];
  String? error;
  DateTime from = DateTime.now().toUtc().subtract(const Duration(days: 7)),
      to = DateTime.now().toUtc().add(const Duration(days: 1));
  bool busy = false;
  List<String> alerts = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    user.dispose();
    device.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> query({int limit = 300}) {
    widget.service.require(Permission.audit);
    final filters = ['a.store_id=?', 'a.client_time>=?', 'a.client_time<?'],
        args = <Object?>[
          widget.service.storeId,
          from.toIso8601String(),
          to.toIso8601String(),
        ];
    void where(String sql, List<Object?> values) {
      filters.add(sql);
      args.addAll(values);
    }

    if (widget.entityId != null) {
      where(
        "(a.entity_id=? OR json_extract(a.changes_json,'\$.original_id')=?)",
        [widget.entityId, widget.entityId],
      );
    }
    if (action.isNotEmpty) where('a.action=?', [action]);
    if (severity.isNotEmpty) where('a.severity=?', [severity]);
    if (search.text.trim().isNotEmpty) {
      where(
        '(a.document_code LIKE ? OR a.entity_id LIKE ? OR a.changes_json LIKE ?)',
        List.filled(3, '%${search.text.trim()}%'),
      );
    }
    if (user.text.trim().isNotEmpty) {
      where('(u.display_name LIKE ? OR a.user_id=?)', [
        '%${user.text.trim()}%',
        user.text.trim(),
      ]);
    }
    if (device.text.trim().isNotEmpty) {
      where('(d.code=? OR a.device_id=?)', [
        device.text.trim(),
        device.text.trim(),
      ]);
    }
    return widget.service.db.rows(
      '''SELECT a.*,r.received_at AS receipt_time,COALESCE(u.display_name,'Hệ thống') AS actor_name,d.code AS device_code FROM audit_logs a LEFT JOIN local_audit_receipts r ON r.store_id=a.store_id AND r.audit_id=a.id LEFT JOIN users u ON u.id=a.user_id LEFT JOIN devices d ON d.id=a.device_id WHERE ${filters.join(' AND ')} ORDER BY a.client_time DESC,a.id DESC LIMIT $limit''',
      args,
    );
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await query(),
          since = widget.service
              .clock()
              .toUtc()
              .subtract(const Duration(days: 1))
              .toIso8601String();
      final counts = await widget.service.db.rows(
        'SELECT action,COUNT(*) AS n FROM audit_logs WHERE store_id=? AND client_time>=? GROUP BY action',
        [widget.service.storeId, since],
      );
      final count = {for (final row in counts) row['action']: row['n'] as int};
      final large = await widget.service.db.rows(
        "SELECT COUNT(*) AS n FROM stock_movements WHERE store_id=? AND kind='adjustment' AND ABS(quantity)>=50 AND created_at>=?",
        [widget.service.storeId, since],
      );
      final discounts = await widget.service.db.rows(
        'SELECT COUNT(*) AS n FROM documents WHERE store_id=? AND issued_at>=? AND subtotal>0 AND discount*100>subtotal*20',
        [widget.service.storeId, since],
      );
      if (mounted) {
        setState(() {
          rows = data;
          alerts = [
            if ((count['LOGIN_FAILED'] ?? 0) >= 5)
              '${count['LOGIN_FAILED']} lần đăng nhập sai trong 24 giờ',
            if ((count['INVOICE_CANCEL'] ?? 0) >= 5)
              '${count['INVOICE_CANCEL']} hóa đơn bị hủy trong 24 giờ',
            if ((large.single['n'] as int) > 0)
              '${large.single['n']} điều chỉnh kho từ 50 đơn vị',
            if ((discounts.single['n'] as int) > 0)
              '${discounts.single['n']} hóa đơn giảm trên 20%',
          ];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (range != null) {
      from = DateTime.utc(
        range.start.year,
        range.start.month,
        range.start.day,
      ).subtract(const Duration(hours: 7));
      to = DateTime.utc(
        range.end.year,
        range.end.month,
        range.end.day + 1,
      ).subtract(const Duration(hours: 7));
      await load();
    }
  }

  Future<void> export(bool pdf) async {
    try {
      final data = await query(limit: 10001);
      if (data.length > 10000) {
        throw StateError(
          'Có hơn 10.000 kết quả. Thu hẹp khoảng ngày trước khi xuất.',
        );
      }
      final headers = [
        'Thời gian máy',
        'Cloud tiếp nhận',
        'Nhân viên',
        'Thiết bị',
        'Thao tác',
        'Chứng từ / đối tượng',
        'Mức độ',
        'Lý do',
        'Trước / sau',
      ];
      final values = [
        for (final r in data)
          <Object?>[
            r['client_time'],
            r['server_time'] ?? r['receipt_time'] ?? '',
            r['actor_name'],
            r['device_code'],
            actionLabels[r['action']] ?? r['action'],
            r['document_code'] ?? r['entity_id'],
            severityLabels[r['severity']],
            r['reason'],
            r['changes_json'],
          ],
      ];
      if (pdf) {
        await saveReportPdf(
          widget.service,
          'Nhật ký thao tác',
          headers,
          values,
        );
      } else {
        await saveReportXlsx(
          widget.service,
          'Nhật ký thao tác',
          headers,
          values,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void detail(Map<String, Object?> r) {
    final text = const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(r['changes_json'] as String));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(actionLabels[r['action']] ?? r['action'] as String),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(
                '${r['actor_name']} · ${r['role']} · ${r['device_code']}\nThời gian máy: ${r['client_time']}\nThời gian cloud: ${r['server_time'] ?? r['receipt_time'] ?? 'Chưa có'}\nĐối tượng: ${r['entity_type']} / ${r['entity_id']}\nLý do: ${r['reason']}\n\nGiá trị trước / sau:\n$text\n\nBăm: ${r['hash']}\nBăm trước: ${r['hash_prev']}',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .55),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Nhật ký thao tác',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: dates,
                        icon: const Icon(Icons.date_range),
                        label: const Text('Khoảng ngày'),
                      ),
                      TextButton(
                        onPressed: () => export(false),
                        child: const Text('Xuất Excel'),
                      ),
                      TextButton(
                        onPressed: () => export(true),
                        child: const Text('Xuất PDF'),
                      ),
                    ],
                  ),
                  for (final alert in alerts)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠ $alert',
                        style: const TextStyle(color: Color(0xffa65e00)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final field in [
                        (search, 'Mã chứng từ / nội dung'),
                        (user, 'Nhân viên'),
                        (device, 'Thiết bị'),
                      ])
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: field.$1,
                            onSubmitted: (_) => load(),
                            decoration: InputDecoration(labelText: field.$2),
                          ),
                        ),
                      SizedBox(
                        width: 250,
                        child: DropdownButtonFormField<String>(
                          initialValue: action,
                          decoration: const InputDecoration(
                            labelText: 'Thao tác',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Tất cả'),
                            ),
                            for (final e in actionLabels.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (value) {
                            action = value!;
                            load();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: severity,
                          decoration: const InputDecoration(
                            labelText: 'Mức độ',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Tất cả'),
                            ),
                            for (final e in severityLabels.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (value) {
                            severity = value!;
                            load();
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Không có nhật ký phù hợp.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    return ListTile(
                      onTap: () => detail(r),
                      leading: Icon(
                        r['severity'] == 'critical'
                            ? Icons.warning_amber_outlined
                            : Icons.history,
                      ),
                      title: Text(
                        actionLabels[r['action']] ?? r['action'] as String,
                      ),
                      subtitle: Text(
                        '${r['actor_name']} · ${r['device_code']} · ${r['client_time']}\n${r['document_code'] ?? r['entity_id']}',
                      ),
                      isThreeLine: true,
                      trailing: Text(severityLabels[r['severity']] ?? ''),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
