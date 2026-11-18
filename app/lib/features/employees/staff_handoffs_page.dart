import 'package:material_ui/material_ui.dart';

import '../../core/sync/cloud_api.dart';
import '../../core/auth/permissions.dart';
import 'personnel_service.dart';

class StaffHandoffsPage extends StatefulWidget {
  const StaffHandoffsPage({super.key, required this.api, this.sync});
  final CloudApi api;
  final Future<void> Function()? sync;
  @override
  State<StaffHandoffsPage> createState() => _StaffHandoffsPageState();
}

class _StaffHandoffsPageState extends State<StaffHandoffsPage> {
  List<Map<String, Object?>> requests = [], devices = [];
  String? store, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool sync = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (sync) await widget.sync?.call();
      final result = await widget.api.send('/staff/handoffs');
      if (mounted) {
        setState(() {
          store = result['store_id'] as String?;
          requests = [
            for (final r in result['requests'] as List)
              Map<String, Object?>.from(r as Map),
          ];
          devices = [
            for (final r in result['devices'] as List)
              Map<String, Object?>.from(r as Map),
          ];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(Map<String, Object?> row, bool commit) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          commit ? 'Hoàn tất bàn giao quyền' : 'Hủy yêu cầu bàn giao',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                commit
                    ? 'Các máy đã xác nhận dừng quyền cũ và gửi hết hàng đợi nghiệp vụ. Hoàn tất sẽ đổi quyền/khóa tài khoản và thu hồi các phiên bị ảnh hưởng.'
                    : 'Hủy chỉ bỏ đóng băng cloud. Nhân viên cần đăng nhập online lại; không tự khôi phục grant cũ trên máy.',
              ),
              if (!commit)
                TextField(
                  controller: reason,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Lý do hủy (bắt buộc)',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(commit ? 'Xác nhận hoàn tất' : 'Hủy bàn giao'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      reason.dispose();
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.send(
        '/staff/handoffs',
        body: {
          'id': row['id'],
          'action': commit ? 'commit' : 'cancel',
          'confirmed': commit,
          if (!commit) 'reason': reason.text,
        },
      );
      await load(sync: true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      reason.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Bàn giao quyền · nhân viên',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Các máy native phải kết nối, xóa quyền offline cũ và gửi hết hàng đợi. Không bỏ giao dịch hoặc coi máy mất là đã đối soát. Ảnh tùy chọn vẫn được giữ trên máy, không chặn bàn giao nghiệp vụ.',
      ),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: busy ? null : () => load(sync: true),
            child: const Text('Đồng bộ máy này · tải lại'),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        SelectableText(error!, style: const TextStyle(color: Colors.red)),
      if (requests.isEmpty && !busy)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Chưa có yêu cầu bàn giao. Đổi vai trò/khóa nhân viên từ màn Nhân viên để bắt đầu.',
          ),
        ),
      for (final row in requests)
        Builder(
          builder: (_) {
            final payload = Map<String, Object?>.from(row['payload'] as Map),
                pending = row['status'] == 'pending',
                rows = devices
                    .where((d) => d['request_id'] == row['id'])
                    .toList();
            final ready =
                    rows.isNotEmpty && rows.every((d) => d['acked_at'] != null),
                local = row['store_id'] == store;
            final role = Role.values.byName(payload['role'] as String);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['name']} · ${row['status'] == 'completed'
                          ? 'Đã bàn giao'
                          : row['status'] == 'cancelled'
                          ? 'Đã hủy'
                          : 'Chờ các máy'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Vai trò mới: ${roleLabels[role]} · ${payload['active'] == true
                          ? 'Đang làm việc'
                          : row['global_lock'] == 1
                          ? 'Khóa toàn tài khoản'
                          : 'Khóa phân công cửa hàng'}',
                    ),
                    Text('Lý do: ${payload['reason']}'),
                    for (final d in rows)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          d['acked_at'] == null
                              ? Icons.hourglass_empty
                              : Icons.verified_outlined,
                        ),
                        title: Text(
                          '${d['store_code']} · ${d['code']} · ${d['name']}',
                        ),
                        subtitle: Text(
                          d['acked_at'] == null
                              ? 'Chờ xác nhận${d['device_status'] == 'revoked' ? ' · Máy đã thu hồi, cần khôi phục/đối soát dữ liệu' : ''}'
                              : 'Đã xác nhận ${d['acked_at']}',
                        ),
                      ),
                    if (pending) ...[
                      if (!local)
                        const Text(
                          'Cần đăng nhập cửa hàng đã tạo yêu cầu để xử lý.',
                        ),
                      const Text(
                        'Grant hết hạn mà còn queue: hủy bàn giao, cho nhân viên đăng nhập online và gửi hết, rồi tạo lại. Máy không truy cập được cần dữ liệu nguồn/đối soát; không tự giải phóng quyền tồn.',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: busy || !ready || !local
                                ? null
                                : () => act(row, true),
                            child: const Text('Hoàn tất bàn giao'),
                          ),
                          TextButton(
                            onPressed: busy || !local
                                ? null
                                : () => act(row, false),
                            child: const Text('Hủy yêu cầu'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
    ],
  );
}
