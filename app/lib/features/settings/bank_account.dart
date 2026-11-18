import 'dart:convert';
import 'dart:typed_data';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

class BankAccount {
  const BankAccount({
    required this.bank,
    required this.number,
    required this.holder,
    this.qr,
  });
  final String bank, number, holder;
  final Uint8List? qr;
  factory BankAccount.fromJson(Map<String, Object?> row) => BankAccount(
    bank: row['bank_name'] as String,
    number: row['account_number'] as String,
    holder: row['account_holder'] as String,
    qr: (row['qr_png'] as String).isEmpty
        ? null
        : base64Decode(row['qr_png'] as String),
  );
  Map<String, Object?> toJson() => {
    'bank_name': bank.trim(),
    'account_number': number.trim(),
    'account_holder': holder.trim(),
    'qr_png': qr == null ? '' : base64Encode(qr!),
  };
  void validate() {
    if (bank.trim().isEmpty ||
        bank.length > 100 ||
        holder.trim().isEmpty ||
        holder.length > 100 ||
        !RegExp(r'^[A-Za-z0-9 .-]{3,40}$').hasMatch(number.trim())) {
      throw ArgumentError(
        'Kiểm tra tên ngân hàng, chủ tài khoản và số tài khoản.',
      );
    }
    final bytes = qr;
    if (bytes != null) {
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 33 ||
          bytes.length > 65536 ||
          List.generate(8, (i) => bytes[i]).join(',') != signature.join(',') ||
          ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
        throw ArgumentError('Ảnh QR phải là PNG tối đa 64KB.');
      }
      final data = ByteData.sublistView(bytes),
          width = data.getUint32(16),
          height = data.getUint32(20);
      if (width < 1 || height < 1 || width > 1024 || height > 1024) {
        throw ArgumentError('Kích thước QR tối đa 1024×1024.');
      }
    }
  }
}

extension BankAccountService on LocalService {
  Future<BankAccount?> bankAccount() async {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    actor.require(Permission.sell, storeId, clock());
    return readBankAccount();
  }

  Future<BankAccount?> readBankAccount() async {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    if (!actor.can(Permission.sell) && !actor.can(Permission.configure)) {
      throw StateError('Không có quyền xem cấu hình chuyển khoản.');
    }
    actor.require(
      actor.can(Permission.configure) ? Permission.configure : Permission.sell,
      storeId,
      clock(),
    );
    final rows = await db.rows(
      'SELECT config_json FROM bank_accounts WHERE store_id=?',
      [storeId],
    );
    if (rows.isEmpty) return null;
    final result = BankAccount.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['config_json'] as String) as Map,
      ),
    );
    result.validate();
    return result;
  }

  Future<void> saveBankAccount(BankAccount account, String reason) async {
    final actor = require(Permission.configure);
    account.validate();
    if (reason.trim().isEmpty || reason.length > 200) {
      throw ArgumentError('Nhập lý do tối đa 200 ký tự.');
    }
    await db.transaction(() async {
      if (require(Permission.configure).userId != actor.userId) {
        throw StateError('Phiên đã thay đổi.');
      }
      final previous = await readBankAccount(), stamp = now;
      await db.execute(
        'INSERT INTO bank_accounts VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET device_id=excluded.device_id,user_id=excluded.user_id,config_json=excluded.config_json,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          storeId,
          storeId,
          deviceId,
          actor.userId,
          jsonEncode(account.toJson()),
          stamp,
          '$stamp|$deviceId|${uuid.v7()}',
        ],
      );
      Map<String, Object?> snapshot(BankAccount value) => {
        'bank_name': value.bank,
        'account_last_four': value.number.length < 4
            ? value.number
            : value.number.substring(value.number.length - 4),
        'has_qr': value.qr != null,
      };
      await audit(
        'BANK_ACCOUNT_SAVE',
        'store',
        storeId,
        reason: reason.trim(),
        severity: 'sensitive',
        changes: {
          'before': previous == null ? null : snapshot(previous),
          'after': snapshot(account),
        },
      );
      await enqueue('bank_account', {'id': storeId}, 3);
    });
  }
}
