import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../audit/audit_page.dart';
import 'sales_service.dart';
import 'document_pdf.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key, required this.service});
  final LocalService service;
  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  late Future<List<Map<String, Object?>>> data;
  final money = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );
  @override
  void initState() {
    super.initState();
    data = widget.service.invoices();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Hóa đơn bán hàng',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => data = widget.service.invoices()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('Chưa phát hành hóa đơn.'));
              }
              return ListView.separated(
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final invoice = snapshot.data![index];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long),
                      ),
                      title: Text(
                        '${invoice['code']}${invoice['cancelled'] == 1 ? ' · Đã hủy' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${invoice['issued_at']}\n${money.format(invoice['total'])} · Đã thu ${money.format(invoice['paid'])}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.service.session?.can(Permission.audit) ??
                              false)
                            IconButton(
                              tooltip: 'Lịch sử thao tác',
                              icon: const Icon(Icons.history),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(
                                      title: Text('Nhật ký ${invoice['code']}'),
                                    ),
                                    body: AuditPage(
                                      service: widget.service,
                                      entityId: invoice['id'] as String,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Xem / lưu PDF',
                            onPressed: () async {
                              try {
                                await showInvoicePdf(
                                  context,
                                  widget.service,
                                  invoice['id'] as String,
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
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
