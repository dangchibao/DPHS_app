import 'package:material_ui/material_ui.dart';

import '../../core/sync/cloud_api.dart';
import '../../core/money.dart';
import 'cloud_reports.dart';
import 'report_service.dart';

class OnlineReportsPage extends StatefulWidget {
  const OnlineReportsPage({
    super.key,
    required this.api,
    required this.exportAction,
    this.storeId,
    this.clock,
  });
  final CloudApi api;
  final String? storeId;
  final DateTime Function()? clock;
  final Future<void> Function(String, ReportTable, bool) exportAction;
  @override
  State<OnlineReportsPage> createState() => _OnlineReportsPageState();
}

class _OnlineReportsPageState extends State<OnlineReportsPage> {
  late final client = CloudReports(widget.api),
      today = (widget.clock ?? DateTime.now)()
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
  late final from = TextEditingController(text: '${today.substring(0, 7)}-01'),
      to = TextEditingController(text: today);
  final year = TextEditingController();
  List<Map<String, Object?>> stores = [], schools = [];
  String? store, school, error;
  String selected = 'Doanh thu theo ngày', notice = '';
  bool busy = false, canAll = false;
  int visible = 200;
  ReportData? data;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    year.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    setState(() => busy = true);
    try {
      if (widget.api.token == null) {
        throw StateError('Cần đăng nhập cloud để xem báo cáo online.');
      }
      final options = await client.options();
      if (!mounted) return;
      setState(() {
        stores = [
          for (final row in options['stores'] as List)
            Map<String, Object?>.from(row as Map),
        ];
        schools = [
          for (final row in options['schools'] as List)
            Map<String, Object?>.from(row as Map),
        ];
        canAll = options['can_all_stores'] == true;
        store = stores.any((s) => s['id'] == widget.storeId)
            ? widget.storeId
            : stores.firstOrNull?['id'] as String?;
        error = null;
      });
      if (store != null) await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final value = await client.read(
        ReportRange(
          from.text.trim(),
          to.text.trim(),
          year: year.text,
          schoolId: school,
        ),
        store!,
        isCancelled: () => !mounted,
      );
      if (mounted) {
        setState(() {
          data = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> rebuild() async {
    setState(() {
      busy = true;
      notice = 'Đang chuẩn bị bảng tổng hợp...';
    });
    try {
      var count = 0, more = true;
      for (var request = 0; request < 25 && more && mounted; request++) {
        final result = await client.rebuild(store!);
        count += result['processed'] as int;
        more = result['has_more'] == true;
        if (mounted) {
          setState(
            () => notice = 'Đã chuẩn bị $count chứng từ trong lượt này.',
          );
        }
      }
      if (mounted) {
        setState(
          () => notice = more
              ? 'Đã chuẩn bị $count chứng từ; bấm tiếp nếu còn dữ liệu cũ.'
              : 'Bảng tổng hợp đã sẵn sàng.',
        );
      }
      if (!more && mounted) await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> export(bool pdf) async {
    setState(() => busy = true);
    try {
      final filter = data!.range,
          schoolName =
              schools
                  .where((s) => s['id'] == data!.range.schoolId)
                  .firstOrNull?['name'] ??
              'Tất cả';
      await widget.exportAction(
        '${data!.storeLabel} | $selected | ${filter.fromDay} - ${filter.toDay} | Năm: ${filter.year?.isNotEmpty == true ? filter.year : 'Tất cả'} | Trường: $schoolName',
        data!.tables[selected]!,
        pdf,
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = data?.tables[selected];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Dashboard cloud · nhiều cửa hàng',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Cần Internet. Doanh thu/lãi gộp theo khoảng ngày; tồn và công nợ là hiện trạng khi đọc, không phải số dư lịch sử cuối kỳ. Không có bán hàng offline trên Web.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (notice.isNotEmpty) Text(notice),
        const SizedBox(height: 16),
        if (stores.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: store,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cửa hàng'),
            items: [
              if (canAll)
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Tổng toàn hệ thống'),
                ),
              ...stores.map(
                (s) => DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text(
                    '${s['code']} · ${s['name']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() {
                    store = value;
                    school = null;
                  }),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: from,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Từ ngày YYYY-MM-DD',
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: to,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Đến ngày YYYY-MM-DD',
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: year,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Năm học (tất cả nếu trống)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(store),
          initialValue: school ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Trường'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tất cả trường')),
            for (final s in schools.where(
              (s) => store == 'all' || s['store_id'] == store,
            ))
              DropdownMenuItem(
                value: s['id'] as String,
                child: Text(
                  s['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => school = value?.isEmpty == true ? null : value,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: busy
                  ? null
                  : store == null
                  ? initialize
                  : load,
              child: const Text('Xem báo cáo online'),
            ),
            if (canAll)
              OutlinedButton(
                onPressed: busy || store == null || store == 'all'
                    ? null
                    : rebuild,
                child: const Text('Chuẩn bị dữ liệu cũ'),
              ),
          ],
        ),
        if (data != null) ...[
          const Divider(height: 32),
          Text(
            data!.storeLabel,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            '${data!.range.fromDay} đến ${data!.range.toDay} · Chốt số liệu tài chính lúc ${data!.generatedAt}',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in {
                'revenue': 'Doanh thu thuần',
                'gross_profit': 'Lãi gộp',
                'cashflow': 'Thu trừ hoàn',
                'debt': 'Công nợ hiện tại',
                'overdue': 'Nợ quá hạn hiện tại',
              }.entries)
                SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.value),
                          const SizedBox(height: 8),
                          Text(
                            formatWholeVnd(data!.totals[item.key]!),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Text(
            'Phiếu bán/may: ${data!.totals['invoices']} · Đổi trả: ${data!.totals['returns']} · Đơn may: ${data!.totals['tailoring']}',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Loại báo cáo'),
            items: [
              for (final name in data!.tables.keys)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() {
                    selected = value!;
                    visible = 200;
                  }),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: busy ? null : () => export(false),
                child: const Text('Xuất Excel'),
              ),
              TextButton(
                onPressed: busy ? null : () => export(true),
                child: const Text('Xuất PDF'),
              ),
            ],
          ),
          if (table != null && table.rows.isEmpty)
            const Text('Không có dữ liệu phù hợp.'),
          if (table != null && table.rows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final h in table.headers) DataColumn(label: Text(h)),
                ],
                rows: [
                  for (final row in table.rows.take(visible))
                    DataRow(
                      cells: [
                        for (var c = 0; c < row.length; c++)
                          DataCell(
                            Text(
                              row[c] is BigInt
                                  ? table.moneyColumns.contains(c)
                                        ? formatWholeVnd(row[c] as BigInt)
                                        : (row[c] as BigInt).toString()
                                  : '${row[c] ?? ''}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          if (table != null && table.rows.length > visible)
            TextButton(
              onPressed: () => setState(() => visible += 200),
              child: Text('Xem thêm · $visible/${table.rows.length} dòng'),
            ),
        ],
      ],
    );
  }
}
