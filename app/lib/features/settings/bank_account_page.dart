import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/local_service.dart';
import '../../core/media/image_encoder.dart';
import 'bank_account.dart';

class BankAccountPage extends StatefulWidget {
  const BankAccountPage({super.key, required this.service});
  final LocalService service;
  @override
  State<BankAccountPage> createState() => _BankAccountPageState();
}

class _BankAccountPageState extends State<BankAccountPage> {
  final bank = TextEditingController(),
      number = TextEditingController(),
      holder = TextEditingController(),
      reason = TextEditingController();
  Uint8List? qr;
  String? error, notice;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [bank, number, holder, reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final account = await widget.service.readBankAccount();
      if (account != null && mounted) {
        bank.text = account.bank;
        number.text = account.number;
        holder.text = account.holder;
        qr = account.qr;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> select() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (file == null) return;
      if ((file.lengthSync() ?? 0) > 8 * 1024 * 1024) {
        throw ArgumentError('Chọn ảnh tối đa 8MB.');
      }
      final data = BytesBuilder(copy: false);
      await for (final part in file.readAsByteStream()) {
        if (data.length + part.length > 8 * 1024 * 1024) {
          throw ArgumentError('Chọn ảnh tối đa 8MB.');
        }
        data.add(part);
      }
      final result = await prepareImage(data.takeBytes(), qr: true);
      if (mounted) setState(() => qr = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.service.saveBankAccount(
        BankAccount(
          bank: bank.text,
          number: number.text,
          holder: holder.text,
          qr: qr,
        ),
        reason.text,
      );
      if (mounted) {
        setState(() {
          notice = 'Đã lưu trên máy; cấu hình sẽ tự đồng bộ tới các máy cùng cửa hàng.';
          reason.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Tài khoản · QR chuyển khoản',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Cấu hình riêng cửa hàng. Ảnh QR tĩnh không tự điền số tiền/nội dung và không xác nhận đã nhận tiền. Thu ngân kiểm tra giao dịch ngân hàng trước khi ghi thanh toán.',
      ),
      if (busy) const LinearProgressIndicator(),
      for (final entry in [
        (bank, 'Ngân hàng'),
        (number, 'Số tài khoản'),
        (holder, 'Chủ tài khoản'),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: entry.$1,
            enabled: !busy,
            decoration: InputDecoration(labelText: entry.$2),
          ),
        ),
      if (qr != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Image.memory(
            qr!,
            height: 280,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Text('Không đọc được ảnh QR. Chọn ảnh khác.'),
          ),
        ),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : select,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Chọn ảnh QR PNG/JPEG'),
          ),
          TextButton(
            onPressed: busy || qr == null
                ? null
                : () => setState(() => qr = null),
            child: const Text('Bỏ ảnh QR'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: reason,
        enabled: !busy,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Lý do thay đổi (bắt buộc)',
        ),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('Lưu cấu hình cửa hàng'),
      ),
      for (final text in [error, notice])
        if (text != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(
              text,
              style: TextStyle(color: text == error ? Colors.red : null),
            ),
          ),
    ],
  );
}

class BankTransferDetails extends StatelessWidget {
  const BankTransferDetails({super.key, required this.account});
  final BankAccount? account;
  @override
  Widget build(BuildContext context) {
    final value = account;
    if (value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: ListTile(
          leading: Icon(Icons.qr_code_2, size: 42),
          title: Text('QR chuyển khoản'),
          subtitle: Text(
            'Chưa cấu hình tài khoản của cửa hàng. Chỉ ghi nhận tiền thực tế đã nhận.',
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: Text('${value.bank} · ${value.number}'),
          subtitle: Text(value.holder),
        ),
        if (value.qr != null)
          Center(
            child: Image.memory(
              value.qr!,
              height: 240,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text(
                'Ảnh QR không hợp lệ. Dùng số tài khoản phía trên.',
              ),
            ),
          ),
        const Text(
          'QR tĩnh · Kiểm tra số tiền, nội dung và tiền thực nhận trước khi xác nhận.',
        ),
      ],
    );
  }
}
