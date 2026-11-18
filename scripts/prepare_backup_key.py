"""Prepare an owner-held GPG key outside the repo; never upload private keys."""
import argparse
import datetime as dt
import json
import os
import tempfile
from pathlib import Path

import cloud_backup as backup


def fingerprint(listing):
    found, primary = [], False
    for line in listing.decode().splitlines():
        fields = line.split(':')
        if fields[0] in ('sec', 'pub'):
            primary = True
        elif fields[0] == 'fpr' and primary:
            found.append(fields[9].upper())
            primary = False
    if len(found) != 1:
        raise ValueError('Managed keyring phải có đúng một primary key.')
    return found[0]


def prepare(folder, create=False, drill_sql=None):
    password = os.environ.get('NT_BACKUP_KEY_PASSPHRASE', '')
    if len(password) < 24 or '\n' in password or '\r' in password:
        raise ValueError('Thiếu passphrase mạnh qua môi trường riêng.')
    home = folder / 'cloud-backup-gpg'
    public = folder / 'cloud-backup-public.asc'
    private = folder / 'cloud-backup-private.asc'
    has_backup = public.exists() or private.exists()
    if not home.exists():
        if has_backup:
            raise ValueError('Đã có backup khóa; cần phục hồi keyring, không tự tạo khóa khác.')
        if not create:
            raise ValueError('Chưa có keyring; cần --create-key cho lần tạo đầu.')
        home.mkdir(parents=True, mode=0o700)
    env = {**os.environ, 'GNUPGHOME': str(home)}
    secret = backup.command(['gpg', '--batch', '--with-colons', '--list-secret-keys'], env=env)
    if b'sec:' not in secret:
        if has_backup:
            raise ValueError('Đã có backup khóa; cần phục hồi keyring, không tự tạo khóa khác.')
        if not create:
            raise ValueError('Chưa có khóa; cần --create-key cho lần tạo đầu.')
        backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                        '--quick-generate-key', 'Ngoc Thanh POS Backup', 'rsa3072', 'encr', '2y'],
                       input=(password + '\n').encode(), env=env)
        secret = backup.command(['gpg', '--batch', '--with-colons', '--list-secret-keys'], env=env)
    fpr = fingerprint(secret)
    if not public.exists():
        content = backup.command(['gpg', '--batch', '--armor', '--export', fpr], env=env)
        with public.open('xb') as file:
            file.write(content)
    if fingerprint(backup.command(['gpg', '--batch', '--with-colons', '--show-keys', str(public)], env=env)) != fpr:
        raise ValueError('Public key hiện có không khớp; không ghi đè.')
    if not private.exists():
        content = backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                                  '--armor', '--export-secret-keys', fpr],
                                 input=(password + '\n').encode(), env=env)
        with private.open('xb') as file:
            file.write(content)
    if fingerprint(backup.command(['gpg', '--batch', '--with-colons', '--show-keys', str(private)], env=env)) != fpr:
        raise ValueError('Private key backup không khớp; không ghi đè.')
    result = {'fingerprint': fpr, 'public_key': str(public), 'private_key_backup': str(private),
              'private_key_uploaded': False, 'cloud_changed': False}
    if drill_sql is not None:
        with tempfile.TemporaryDirectory(prefix='nt-owner-gpg-drill-') as name:
            temp = Path(name)
            bundle, decrypted = temp / 'database.tar.gz', temp / 'decrypted.tar.gz'
            manifest = backup.make_bundle(drill_sql, bundle, dt.datetime.now(dt.timezone.utc))
            ciphertext = folder / ('cloud-backup-drill-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '.tar.gz.gpg')
            if ciphertext.exists():
                raise ValueError('Tên bản diễn tập đã có; không ghi đè.')
            backup.encrypt(bundle, ciphertext, public.read_text(encoding='utf8'), fpr)
            # Import the exported private key into a NEW keyring: recovery must
            # not depend on the original keyring or its agent cache.
            restore_home = temp / 'restore-keyring'
            restore_home.mkdir(mode=0o700)
            restore_env = {**os.environ, 'GNUPGHOME': str(restore_home)}
            try:
                backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                                '--import', str(private)], input=(password + '\n').encode(), env=restore_env)
                backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                                '--output', str(decrypted), '--decrypt', str(ciphertext)],
                               input=(password + '\n').encode(), env=restore_env)
                if backup.digest(decrypted) != backup.digest(bundle):
                    raise ValueError('Ciphertext giải mã không khớp checksum bundle.')
                backup.verify_bundle(decrypted)
            finally:
                # Stop only the agent belonging to this temporary keyring.
                backup.command(['gpgconf', '--kill', 'gpg-agent'], env=restore_env)
            result.update({'encrypted_drill': str(ciphertext), 'ciphertext_sha256': backup.digest(ciphertext),
                           'exported_private_key_restore': 'passed', 'bundle_checksum': 'passed',
                           'schema_version': manifest['schema_version']})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create-key', action='store_true')
    parser.add_argument('--drill-sql', type=Path)
    args = parser.parse_args()
    local = os.environ.get('LOCALAPPDATA')
    if not local:
        raise ValueError('Công cụ này cần Windows LOCALAPPDATA, không dùng keyring mặc định.')
    folder = Path(local) / 'NgocThanhPOSDeployment'
    result = prepare(folder, args.create_key, args.drill_sql)
    (folder / 'cloud-backup-key-info.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # GPG stderr/SQL/key packets/passphrase must never reach logs.
        print(json.dumps({'status': 'failed', 'error_type': type(error).__name__,
                          'message': 'Chuẩn bị khóa hoặc diễn tập không đạt; không ghi đè khóa có sẵn.'}, ensure_ascii=False))
        raise SystemExit(1)
