"""Owner-only restore drill for the latest encrypted Windows D1 backup."""
import argparse
import json
import os
from pathlib import Path
import tempfile

import cloud_backup as backup


def verify(report_path, private_key, password):
    if not password or '\n' in password or '\r' in password:
        raise ValueError('Thiếu passphrase qua môi trường riêng.')
    report = json.loads(Path(report_path).read_text(encoding='utf-8-sig'))
    if report.get('status') != 'success' or report.get('mode') != 'local_encrypted_no_r2':
        raise ValueError('Chưa có backup hoàn tất để diễn tập.')
    cipher = Path(report['encrypted_file'])
    checksum = backup.digest(cipher)
    if checksum != report['ciphertext_sha256'] or checksum != Path(str(cipher) + '.sha256').read_text().strip():
        raise ValueError('Checksum ciphertext không khớp.')
    # Short temporary paths work with Git for Windows GPG agent/socket limits.
    with tempfile.TemporaryDirectory(prefix='nt-restore-') as name:
        temp = Path(name)
        home = temp / 'keyring'
        home.mkdir(mode=0o700)
        env = {**os.environ, 'GNUPGHOME': str(home)}
        secret = (password + '\n').encode()
        try:
            backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                            '--import', str(private_key)], input=secret, env=env)
            bundle = temp / 'database.tar.gz'
            backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                            '--output', str(bundle), '--decrypt', str(cipher)], input=secret, env=env)
            manifest = backup.verify_bundle(bundle)
            if manifest['schema_version'] != report['schema_version']:
                raise ValueError('Schema không khớp bản đã kiểm chứng.')
            return {'status': 'success', 'database_id': report['database_id'],
                    'ciphertext_sha256': checksum, 'schema_version': manifest['schema_version'],
                    'fresh_private_keyring_restore': 'passed', 'r2_used': False}
        finally:
            backup.command(['gpgconf', '--kill', 'gpg-agent'], env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--private-key', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.report, args.private_key, os.environ.get('NT_BACKUP_KEY_PASSPHRASE'))
    except Exception as error:
        result = {'status': 'failed', 'error_type': type(error).__name__,
                  'message': 'Diễn tập giải mã/restore chưa đạt; không công nhận bằng chứng mới.'}
    args.proof.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['status'] == 'success' else 1


if __name__ == '__main__':
    raise SystemExit(main())
