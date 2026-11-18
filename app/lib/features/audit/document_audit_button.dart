import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'audit_page.dart';

class DocumentAuditButton extends StatelessWidget {
  const DocumentAuditButton({
    super.key,
    required this.service,
    required this.documentId,
    this.compact = false,
  });
  final LocalService service;
  final String documentId;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (service.session?.can(Permission.audit) != true) {
      return const SizedBox.shrink();
    }
    void open() {
      service.require(Permission.audit);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Lịch sử chứng từ')),
            body: AuditPage(service: service, entityId: documentId),
          ),
        ),
      );
    }

    if (compact) {
      return IconButton(
        onPressed: open,
        icon: const Icon(Icons.history),
        tooltip: 'Lịch sử thay đổi',
      );
    }
    return TextButton.icon(
      onPressed: open,
      icon: const Icon(Icons.history),
      label: const Text('Lịch sử thay đổi'),
    );
  }
}
