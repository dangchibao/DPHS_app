import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/sync/cloud_api.dart';

class CloudUsagePage extends StatefulWidget {
  const CloudUsagePage({super.key, required this.api, this.compact = false});
  final CloudApi api;
  final bool compact;
  @override
  State<CloudUsagePage> createState() => _CloudUsagePageState();
}

class _CloudUsagePageState extends State<CloudUsagePage> {
  Map<String, Object?>? data;
  String? error;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    if (widget.compact) {
      timer = Timer.periodic(const Duration(minutes: 5), (_) => load());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.send('/usage');
      if (mounted) {
        setState(() {
          data = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static String number(Object? value) {
    if (value == null) return 'Chưa có số đo';
    return value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = data,
        meters = [
          for (final row in (value?['meters'] as List? ?? []))
            Map<String, Object?>.from(row as Map),
        ];
    final warning = meters
        .where((m) => ['warning', 'limit'].contains(m['level']))
        .toList();
    if (widget.compact) {
      if (error != null || value == null) return const SizedBox.shrink();
      if (warning.isEmpty &&
          value['state'] == 'analytics' &&
          meters.every((m) => m['used'] != null)) {
        return const SizedBox.shrink();
      }
      return Card(
        color: const Color(0xfffff4df),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber),
          title: Text(
            warning.isEmpty
                ? 'Chưa có số đo hạn mức cloud đầy đủ'
                : warning
                      .map((m) => '${m['label']}: ${m['percent']}%')
                      .join(' · '),
          ),
          subtitle: Text(
            'Ngày UTC ${value['day_utc']} · Reset 07:00 Việt Nam. Native tiếp tục bán khi cloud bị giới hạn.',
          ),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Hạn mức cloud')),
                  body: CloudUsagePage(api: widget.api),
                ),
              ),
            ),
            child: const Text('Chi tiết'),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Hạn mức cloud · dành cho chủ',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Theo dõi account Cloudflare và database POS. Không tự nâng gói hoặc bật thanh toán.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Cập nhật số đo'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          SelectableText(error!, style: const TextStyle(color: Colors.red)),
        if (value != null) ...[
          Text(
            'Ngày UTC: ${value['day_utc']} · Đọc lúc: ${value['generated_at']}',
          ),
          const Text(
            'Reset hạn mức ngày: 07:00 giờ Việt Nam. Server cache số đo ít nhất 60 giây.',
          ),
          if (value['state'] != 'analytics')
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Chưa có số Analytics: cần cấu hình token Analytics chỉ đọc ở Worker hoặc kiểm tra Cloudflare Dashboard. Không coi phần chưa đo là đã dùng 0.',
                ),
              ),
            ),
          for (final meter in meters)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meter['label'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${number(meter['used'])} / ${number(meter['limit'])}${meter['percent'] == null ? '' : ' · ${meter['percent']}%'}',
                    ),
                    if (meter['percent'] != null)
                      LinearProgressIndicator(
                        value: ((meter['percent'] as num) / 100).clamp(
                          0.0,
                          1.0,
                        ),
                        color: meter['level'] == 'limit'
                            ? Colors.red
                            : meter['level'] == 'warning'
                            ? Colors.orange
                            : null,
                      ),
                    if (meter['level'] == 'warning' ||
                        meter['level'] == 'limit')
                      const Text(
                        'Gần/vượt ngân sách cấu hình. Kiểm tra số đo trên Cloudflare, giảm tải ảnh/báo cáo và giữ nguyên queue trên máy.',
                      ),
                  ],
                ),
              ),
            ),
          Text(
            'CPU tối đa theo cấu hình: ${value['cpu_limit_ms']} ms/request. Chưa đo CPU từng request trong màn này.',
          ),
          Text(
            'Dung lượng toàn account D1 theo cấu hình: ${number(value['account_storage_limit_bytes'])} byte. Cần kiểm tra các database/bucket khác.',
          ),
          Text(value['note'] as String),
          const Divider(),
          const Text(
            'Tham khảo mô phỏng: 900 hóa đơn/ngày, 3 cửa hàng, 10 máy, 4 dòng/hóa đơn đã ước tính khoảng 96,5 nghìn rows written. Chưa gồm mọi nghiệp vụ/ảnh/retry, không coi đây là mức tải an toàn trong Free.',
          ),
          const Text(
            'Khi cloud đạt giới hạn: Windows/Android vẫn lưu giao dịch và queue, không xóa dữ liệu để thử đồng bộ lại. Web cần mạng. Hướng dẫn nâng gói thủ công nằm trong docs/operations/cloud-usage.md.',
          ),
          for (final url in value['sources'] as List)
            SelectableText(url as String),
        ],
      ],
    );
  }
}
