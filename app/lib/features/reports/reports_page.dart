import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../../core/money.dart';
import '../../core/export/report_export.dart';
import 'report_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.service});
  final LocalService service;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final today = widget.service
      .clock()
      .toUtc()
      .add(const Duration(hours: 7))
      .toIso8601String()
      .substring(0, 10);
  late final from = TextEditingController(text: '${today.substring(0, 7)}-01'),
      to = TextEditingController(text: today);
  final year = TextEditingController();
  String? school, error;
  String selected = 'Doanh thu theo ngày';
  bool busy = false;
  int visibleRows = 200;
  ReportData? data;
  List<Map<String, Object?>> schools = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    year.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final range = ReportRange(
        from.text.trim(),
        to.text.trim(),
        year: year.text,
        schoolId: school,
      );
      final result = await widget.service.localReport(
            range,
            isCancelled: () => !mounted,
          ),
          roster = await widget.service.reportSchools();
      if (mounted) {
        setState(() {
          data = result;
          schools = roster;
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

  Future<void> export(bool pdf) async {
    setState(() => busy = true);
    try {
      widget.service.require(Permission.reports);
      final table = data!.tables[selected]!;
      final filter = data!.range;
      final schoolName =
          schools
              .where((s) => s['id'] == filter.schoolId)
              .firstOrNull?['name'] ??
          'Tất cả';
      final name =
          '${data!.storeLabel} | $selected ${filter.fromDay} - ${filter.toDay} | Năm học: ${filter.year?.isNotEmpty == true ? filter.year : 'Tất cả'} | Trường: $schoolName';
      if (pdf) {
        final rows = <List<Object?>>[
          for (final row in table.rows)
            [
              for (var c = 0; c < row.length; c++)
                if (row[c] is BigInt)
                  table.moneyColumns.contains(c)
                      ? formatWholeVnd(row[c] as BigInt)
                      : (row[c] as BigInt).toString()
                else
                  row[c],
            ],
        ];
        await saveReportPdf(widget.service, name, table.headers, rows);
      } else {
        await saveReportXlsx(
          widget.service,
          name,
          table.headers,
          table.excelRows(),
          moneyColumns: table.moneyColumns,
        );
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

  @override
  Widget build(BuildContext context) {
    final table = data?.tables[selected];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Dashboard · báo cáo',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Dữ liệu cửa hàng đã có trên máy, dùng được khi mất mạng. Công nợ tính đến cuối ngày đã chọn; tồn kho là số hiện tại của cửa hàng, không chia theo trường.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
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
                  labelText: 'Năm học (để trống = tất cả)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: school ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Trường'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tất cả trường')),
            ...schools.map(
              (s) => DropdownMenuItem(
                value: s['id'] as String,
                child: Text(
                  s['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: busy
              ? null
              : (value) => school = value?.isEmpty == true ? null : value,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : load,
            child: const Text('Xem báo cáo'),
          ),
        ),
        if (data != null) ...[
          Text(
            data!.storeLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Kết quả đã tải: ${data!.range.fromDay} đến ${data!.range.toDay}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in {
                'revenue': 'Doanh thu thuần',
                'gross_profit': 'Lãi gộp',
                'cashflow': 'Thu trừ hoàn',
                'debt': 'Công nợ cuối kỳ',
                'overdue': 'Nợ quá hạn cuối kỳ',
              }.entries)
                SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.value),
                          const SizedBox(height: 8),
                          Text(
                            formatWholeVnd(data!.totals[entry.key]!),
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
            'Phiếu bán/may: ${data!.totals['invoices']} · Phiếu đổi trả: ${data!.totals['returns']} · Đơn may: ${data!.totals['tailoring']}',
          ),
          const Divider(height: 32),
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
                    visibleRows = 200;
                  }),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => export(false),
                child: const Text('Xuất Excel'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => export(true),
                child: const Text('Xuất PDF'),
              ),
            ],
          ),
          if (table != null && table.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Không có dữ liệu phù hợp.'),
            ),
          if (table != null && table.rows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final h in table.headers) DataColumn(label: Text(h)),
                ],
                rows: [
                  for (final row in table.rows.take(visibleRows))
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
          if (table != null && table.rows.length > visibleRows)
            TextButton(
              onPressed: () => setState(() => visibleRows += 200),
              child: Text('Xem thêm · $visibleRows/${table.rows.length} dòng'),
            ),
        ],
      ],
    );
  }
}
