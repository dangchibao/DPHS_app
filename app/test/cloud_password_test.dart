import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/password.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Credential cloud khớp PBKDF2 chuẩn và giữ khoảng trắng mật khẩu',
    () async {
      expect(
        await Passwords.cloudCredential(' test password ', 'salt-test'),
        '5319ae1b92508b98cbdd9d219a5b10190323977c25dfb2568ce17c4ee1855f36',
      );
    },
  );
}
