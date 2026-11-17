import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import 'debt_service.dart';

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key, required this.service});
  final LocalService service;
  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  bool overdue = false;
  late Future<List<Map<String, Object?>>> data;
  final money = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    data = widget.service.debts(overdueOnly: overdue);
  }

  Future<void> collect(Map<String, Object?> row) async {
    final amount = TextEditingController(text: '${row['balance']}'),
        note = TextEditingController(text: 'Thu công nợ ${row['code']}');
    var method = 'cash', busy = false;
    String? error;
    final commandId = widget.service.uuid.v7();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Thu nợ · ${row['code']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${row['name']} · Còn nợ ${money.format(row['balance'])}',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amount,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số tiền thu (VND)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Phương thức'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
                      DropdownMenuItem(
                        value: 'bank',
                        child: Text('Chuyển khoản'),
                      ),
                    ],
                    onChanged: busy ? null : (v) => method = v!,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung thu',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialog(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final value = int.tryParse(amount.text.trim());
                        if (value == null) {
                          throw ArgumentError('Nhập số tiền nguyên.');
                        }
                        await widget.service.collectDebt(
                          documentId: row['id'] as String,
                          amount: value,
                          method: method,
                          note: note.text,
                          commandId: commandId,
                        );
                        if (dialog.mounted) Navigator.pop(dialog);
                        if (mounted) setState(refresh);
                      } catch (e) {
                        if (dialog.mounted) {
                          setDialog(() {
                            error = e.toString().replaceFirst(
                              'Bad state: ',
                              '',
                            );
                            busy = false;
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Đang ghi nhận…' : 'Ghi nhận thu tiền'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
  }

  Future<void> history(Map<String, Object?> row) async {
    try {
      final rows = await widget.service.paymentHistory(row['id'] as String);
      final credits = await widget.service.debtCredits(row['id'] as String);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Lịch sử thu · ${row['code']}'),
          content: SizedBox(
            width: 560,
            height: 360,
            child: ListView(
              children: [
                for (final p in rows)
                  ListTile(
                    title: Text(
                      '${money.format(p['amount'])} · ${p['method'] == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'}',
                    ),
                    subtitle: Text(
                      '${p['created_at']} · ${p['display_name']}\n${p['note']}',
                    ),
                  ),
                for (final credit in credits)
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(
                      'Cấn nợ ${money.format(-(credit['amount'] as int))}',
                    ),
                    subtitle: Text(
                      '${credit['code']} · ${credit['created_at']}',
                    ),
                  ),
              ],
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chỉ nợ quá hạn'),
                value: overdue,
                onChanged: (v) => setState(() {
                  overdue = v;
                  refresh();
                }),
              ),
            ),
            IconButton(
              onPressed: () => setState(refresh),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          'Thu offline trên thiết bị lập hóa đơn. Mỗi lần thu có nhật ký riêng.',
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(
                  child: Text('Không có công nợ trong danh sách này.'),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['name']} · ${r['code']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text('${r['phone']} · Hạn trả ${r['due_date']}'),
                          Text(
                            'Còn nợ ${money.format(r['balance'])}',
                            style: TextStyle(
                              fontSize: 22,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () => history(r),
                                icon: const Icon(Icons.history),
                                label: const Text('Lịch sử thu'),
                              ),
                              FilledButton.icon(
                                onPressed:
                                    r['device_id'] == widget.service.deviceId
                                    ? () => collect(r)
                                    : null,
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('Thu tiền'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
