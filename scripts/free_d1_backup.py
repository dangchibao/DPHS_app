"""Export an approved D1 database to encrypted LOCAL storage, without R2/AWS."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time

import cloud_backup as backup


def private_destination(path):
    path = Path(os.path.abspath(path))
    # Reject reparse paths before resolving: never redirect backup writes.
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink() or ancestor.is_junction():
            raise ValueError('Thư mục backup không được qua symlink/junction.')
    if path.is_relative_to(backup.ROOT.resolve()):
        raise ValueError('Backup phải nằm ngoài repository.')
    return path


def run(config_path, destination, public_key_path, fingerprint, *, execute=False,
        budget=8_000_000_000):
    if not execute:
        raise ValueError('Cần --execute-cloud để xuất D1 đã được cho phép.')
    config = json.loads(Path(config_path).read_text(encoding='utf-8-sig'))
    bindings = [b for b in config.get('d1_databases', []) if b.get('binding') == 'DB']
    if len(bindings) != 1:
        raise ValueError('Config phải có đúng một binding DB.')
    database = bindings[0].get('database_id', '')
    account = config.get('account_id', '')
    if not re.fullmatch(r'[a-f0-9]{32}', account) or not re.fullmatch(
            r'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}', database):
        raise ValueError('Account/database ID không hợp lệ.')
    if not re.fullmatch(r'[a-fA-F0-9]{40,64}', fingerprint):
        raise ValueError('Cần fingerprint GPG đầy đủ.')
    public_key = Path(public_key_path).read_text(encoding='utf-8')
    if 'PRIVATE KEY' in public_key:
        raise ValueError('Chỉ được dùng public key cho sao lưu.')
    destination = private_destination(Path(destination) / database)
    destination.mkdir(parents=True, exist_ok=True)
    if budget <= 0:
        raise ValueError('Ngân sách ổ đĩa không hợp lệ.')
    # No retention deletion: never delete existing backups to make space.
    used = sum(p.stat().st_size for p in destination.iterdir() if p.is_file())
    if used >= budget:
        raise ValueError('Hết ngân sách ổ đĩa; không xóa bản cũ.')
    lock = destination / '.backup.lock'
    started = time.monotonic()
    # Exclusive lock also protects manual runs from overlapping a scheduled run.
    with lock.open('xb') as lock_file:
        try:
            now = dt.datetime.now(dt.timezone.utc)
            target = destination / (now.strftime('%Y%m%dT%H%M%SZ') + '.tar.gz.gpg')
            sidecar = Path(str(target) + '.sha256')
            if target.exists() or sidecar.exists():
                raise ValueError('Tên backup đã tồn tại; không ghi đè.')
            with tempfile.TemporaryDirectory(prefix='.nt-backup-', dir=destination) as name:
                folder = Path(name)
                export_config = folder / 'wrangler.json'
                export_config.write_text(json.dumps({
                    'name': 'nt-free-local-backup', 'account_id': account,
                    'd1_databases': [{'binding': 'DB', 'database_name': 'backup-target',
                                      'database_id': database}]}), encoding='utf-8')
                sql = folder / 'database.sql'
                npx = shutil.which('npx') or 'npx'
                backup.command([npx, '--no-install', 'wrangler', 'd1', 'export',
                                'backup-target', '--remote', '--skip-confirmation',
                                '--config', str(export_config), '--output', str(sql)],
                               cwd=backup.ROOT / 'api')
                archive = folder / 'database.tar.gz'
                manifest = backup.make_bundle(sql, archive, now)
                backup.verify_bundle(archive)
                encrypted = folder / 'database.gpg'
                backup.encrypt(archive, encrypted, public_key, fingerprint)
                size = encrypted.stat().st_size
                if size == 0 or used + size + 66 > budget:
                    raise ValueError('Vượt ngân sách ổ đĩa; không công nhận bản mới.')
                checksum = backup.digest(encrypted)
                with encrypted.open('rb') as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                    output.flush()
                    os.fsync(output.fileno())
                # Read back the stored bytes before writing the completion marker.
                if backup.digest(target) != checksum:
                    raise ValueError('Checksum sau ghi không khớp; không công nhận bản mới.')
                with sidecar.open('x', encoding='ascii') as output:
                    output.write(checksum + '\n')
                    output.flush()
                    os.fsync(output.fileno())
                return {'status': 'success', 'mode': 'local_encrypted_no_r2',
                        'created_at': now.isoformat(), 'database_id': database,
                        'schema_version': manifest['schema_version'],
                        'encrypted_file': str(target), 'encrypted_bytes': size,
                        'ciphertext_sha256': checksum, 'readback_sha256': 'passed',
                        'local_restore_drill': 'passed', 'r2_used': False,
                        'off_machine_copy': 'not_verified',
                        'd1_export_billing': 'not_measured',
                        'duration_seconds': round(time.monotonic() - started, 1)}
        finally:
            # Only this run's exclusive lock; never recurse or delete backups.
            lock_file.close()
            lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--public-key', required=True, type=Path)
    parser.add_argument('--fingerprint', required=True)
    parser.add_argument('--budget-bytes', type=int, default=8_000_000_000)
    parser.add_argument('--execute-cloud', action='store_true')
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = run(args.config, args.destination, args.public_key, args.fingerprint,
                     execute=args.execute_cloud, budget=args.budget_bytes)
    except Exception as error:
        result = {'status': 'failed', 'error_type': type(error).__name__,
                  'message': 'Backup chưa thành công; giữ nguyên bản cũ. Kiểm tra mạng, đăng nhập Cloudflare, ổ đĩa và cấu hình.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['status'] == 'success' else 1


if __name__ == '__main__':
    raise SystemExit(main())
