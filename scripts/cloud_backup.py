"""D1 export -> local restore drill -> tar/gzip -> public-key encryption -> private R2.

Cloud actions require an explicit --execute-cloud flag. Never imports into D1 or
touches an application's SQLite file. Python standard library; CLI dependencies:
Wrangler (locked api/package-lock.json), GnuPG, AWS CLI v2.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
UTC = dt.timezone.utc
ARCHIVE_RE = re.compile(r"^(\d{8}T\d{6}Z)\.tar\.gz\.gpg$")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def quote(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def restore_sql(sql: Path, target: Path) -> dict:
    """Restore only into a new temporary file, with external file access denied."""
    if target.exists():
        raise ValueError('Đích diễn tập phải là file mới, không ghi đè database.')
    con = sqlite3.connect(target, isolation_level=None)
    try:
        con.enable_load_extension(False)
        con.execute('PRAGMA trusted_schema=OFF')
        allowed_pragmas = {'foreign_keys', 'defer_foreign_keys', 'encoding',
                           'page_size', 'auto_vacuum', 'user_version',
                           'application_id', 'recursive_triggers'}

        def authorize(action, first, second, _db, _trigger):
            if action in (sqlite3.SQLITE_ATTACH, sqlite3.SQLITE_DETACH,
                          sqlite3.SQLITE_CREATE_VTABLE, sqlite3.SQLITE_DROP_VTABLE):
                return sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_FUNCTION and str(second).lower() in (
                    'load_extension', 'readfile', 'writefile'):
                return sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_PRAGMA and str(first).lower() not in allowed_pragmas:
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK

        con.set_authorizer(authorize)
        # sqlite3.complete_statement handles quoted semicolons and trigger bodies.
        # Stream statements rather than holding a full 500MB+ export in RAM.
        pending = ''
        with sql.open(encoding='utf-8-sig') as source:
            for line in source:
                fragments = line.split(';')
                for part in fragments[:-1]:
                    pending += part + ';'
                    if sqlite3.complete_statement(pending):
                        con.execute(pending)
                        pending = ''
                pending += fragments[-1]
        if pending.strip():
            con.execute(pending)
        con.set_authorizer(None)
        con.commit()
        if con.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise ValueError('Integrity check thất bại.')
        if con.execute('PRAGMA foreign_key_check').fetchone():
            raise ValueError('Foreign key check thất bại.')
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name")]
        if 'schema_metadata' not in tables or 'stock_movements' not in tables:
            raise ValueError('Không phải bản sao lưu ứng dụng Ngọc Thanh.')
        mismatch = con.execute('''WITH ledger AS (
          SELECT store_id,variant_id,SUM(quantity) AS quantity FROM stock_movements GROUP BY store_id,variant_id
        ), keys AS (SELECT store_id,variant_id FROM ledger UNION SELECT store_id,variant_id FROM stock_balances)
        SELECT 1 FROM keys k LEFT JOIN ledger l USING(store_id,variant_id)
        LEFT JOIN stock_balances b USING(store_id,variant_id)
        WHERE COALESCE(l.quantity,0)<>COALESCE(b.quantity,0) LIMIT 1''').fetchone()
        if mismatch:
            raise ValueError('Số dư kho khác sổ cái; không công nhận backup hợp lệ.')
        archive_check = {}
        if 'audit_archives' in tables:
            inconsistent = con.execute('''SELECT 1 FROM audit_archives a
              WHERE a.status='committed' AND (
                a.record_count<>(SELECT COUNT(*) FROM audit_archive_receipts r WHERE r.store_id=a.store_id AND r.archive_id=a.id)
                OR NOT EXISTS(SELECT 1 FROM audit_chain_checkpoints c WHERE c.id=a.id AND c.store_id=a.store_id
                  AND c.device_id=a.device_id AND c.direction=a.direction AND c.chain_index=a.last_index AND c.hash=a.last_hash)
                OR a.gzip_hash IS NULL OR length(a.gzip_hash)<>64 OR COALESCE(a.gzip_bytes,0)<1)
              UNION ALL SELECT 1 FROM audit_archive_receipts r JOIN audit_archives a ON a.id=r.archive_id
                WHERE a.status<>'committed' OR r.store_id<>a.store_id OR r.device_id<>a.device_id
                  OR r.chain_index*a.direction NOT BETWEEN a.first_index*a.direction AND a.last_index*a.direction
                  OR EXISTS(SELECT 1 FROM audit_logs l WHERE l.id=r.id OR (l.store_id=r.store_id AND l.device_id=r.device_id AND l.chain_index=r.chain_index))
              UNION ALL SELECT 1 FROM audit_chain_checkpoints c JOIN audit_archives a ON a.id=c.id WHERE a.status<>'committed'
              UNION ALL SELECT 1 FROM audit_archives a WHERE a.status='committed' AND (
                (a.previous_index=0 AND a.previous_hash<>'') OR (a.previous_index<>0 AND NOT EXISTS(
                  SELECT 1 FROM audit_chain_checkpoints c WHERE c.store_id=a.store_id AND c.device_id=a.device_id
                    AND c.direction=a.direction AND c.chain_index=a.previous_index AND c.hash=a.previous_hash)))
              LIMIT 1''').fetchone()
            if inconsistent:
                raise ValueError('Archive/checkpoint/receipt không khớp; không công nhận backup hợp lệ.')
            archive_check = {'audit_archives': 'ok'}
        return {'schema_version': con.execute('SELECT MAX(version) FROM schema_metadata').fetchone()[0],
                'counts': {t: con.execute('SELECT COUNT(*) FROM ' + quote(t)).fetchone()[0] for t in tables},
                'integrity': 'ok', 'foreign_keys': 'ok', 'stock_ledger': 'ok', **archive_check}
    finally:
        con.close()


def make_bundle(sql: Path, destination: Path, created_at: dt.datetime) -> dict:
    with tempfile.TemporaryDirectory(prefix='nt-backup-drill-') as name:
        folder = Path(name)
        manifest = {'format': 1, 'created_at': created_at.isoformat(),
                    'sql_sha256': digest(sql), 'sql_bytes': sql.stat().st_size,
                    **restore_sql(sql, folder / 'drill.sqlite')}
        (folder / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
        with tarfile.open(destination, 'w:gz') as archive:
            archive.add(sql, arcname='database.sql', recursive=False)
            archive.add(folder / 'manifest.json', arcname='manifest.json', recursive=False)
        return manifest


def verify_bundle(bundle: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix='nt-backup-check-') as name:
        folder = Path(name)
        with tarfile.open(bundle, 'r:gz') as archive:
            members = archive.getmembers()
            if {m.name for m in members} != {'database.sql', 'manifest.json'} or len(members) != 2:
                raise ValueError('Gói backup có thành phần không hợp lệ.')
            for member in members:
                if not member.isfile() or member.size > 8 * 1024**3 or (member.name == 'manifest.json' and member.size > 1024**2):
                    raise ValueError('Thành phần backup không hợp lệ/quá lớn.')
                with archive.extractfile(member) as source, (folder / member.name).open('wb') as target:
                    shutil.copyfileobj(source, target)
        manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        sql = folder / 'database.sql'
        if manifest.get('format') != 1 or manifest.get('sql_sha256') != digest(sql) or manifest.get('sql_bytes') != sql.stat().st_size:
            raise ValueError('Checksum/định dạng backup không khớp.')
        verified = restore_sql(sql, folder / 'drill.sqlite')
        if any(manifest.get(k) != v for k, v in verified.items()):
            raise ValueError('Kết quả khôi phục không khớp manifest.')
        return manifest


def retention(keys: list[str], prefix: str, days=30, weeks=4, months=12) -> tuple[set[str], set[str]]:
    """Retain the newest snapshot per latest distinct day/week/month, unioned.

    Only matching timestamped archives under the exact database prefix are
    eligible. Sidecars, unrelated objects, and malformed keys are never deleted.
    """
    if min(days, weeks, months) < 1:
        raise ValueError('Retention phải giữ ít nhất một kỳ mỗi loại.')
    candidates = []
    for key in keys:
        if not key.startswith(prefix):
            continue
        match = ARCHIVE_RE.fullmatch(key[len(prefix):])
        if match:
            try:
                candidates.append((dt.datetime.strptime(match[1], '%Y%m%dT%H%M%SZ').replace(tzinfo=UTC).astimezone(dt.timezone(dt.timedelta(hours=7))), key))
            except ValueError:
                continue
    candidates.sort(reverse=True)
    keep: set[str] = set()
    for count, grouping in [(days, lambda t: t.date()), (weeks, lambda t: t.isocalendar()[:2]), (months, lambda t: (t.year, t.month))]:
        seen = set()
        for timestamp, key in candidates:
            group = grouping(timestamp)
            if group not in seen and len(seen) < count:
                seen.add(group)
                keep.add(key)
    return keep, {key for _, key in candidates} - keep


def command(args: list[str], *, env=None, input=None, cwd=None) -> bytes:
    # Avoid echoing CLI errors/URLs/bodies that may contain credentials or SQL.
    # Git for Windows ships MSYS GnuPG, whose environment paths must be POSIX.
    executable = shutil.which(args[0]) or args[0]
    if os.name == 'nt' and Path(args[0]).name in ('gpg', 'gpgconf') and '/usr/bin/' in executable.replace('\\', '/').lower():
        def msys_path(value):
            path = Path(value)
            return '/' + path.drive[0].lower() + path.as_posix()[2:] if path.is_absolute() and path.drive else value
        args = [args[0], *(msys_path(a) for a in args[1:])]
        env = dict(os.environ if env is None else env)
        if env.get('GNUPGHOME'):
            env['GNUPGHOME'] = msys_path(env['GNUPGHOME'])
    result = subprocess.run(args, input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, cwd=cwd, timeout=1200, check=False)
    if result.returncode:
        raise RuntimeError(f'Công cụ {Path(args[0]).name} thất bại (exit {result.returncode}); không công bố nội dung nhạy cảm.')
    return result.stdout


def encrypt(bundle: Path, output: Path, public_key: str, fingerprint: str):
    if not re.fullmatch(r'[A-Fa-f0-9]{40,64}', fingerprint):
        raise ValueError('Cần fingerprint GPG đầy đủ.')
    with tempfile.TemporaryDirectory(prefix='nt-gpg-') as name:
        os.chmod(name, 0o700)
        env = {**os.environ, 'GNUPGHOME': name}
        command(['gpg', '--batch', '--import'], input=public_key.encode(), env=env)
        if b'sec:' in command(['gpg', '--batch', '--with-colons', '--list-secret-keys'], env=env):
            raise ValueError('Chỉ được cung cấp khóa công khai cho pipeline.')
        listed = command(['gpg', '--batch', '--with-colons', '--list-keys'], env=env).decode()
        primary_fingerprints = []
        primary = False
        for line in listed.splitlines():
            fields = line.split(':')
            if fields[0] == 'pub':
                primary = True
            elif fields[0] == 'fpr' and primary:
                primary_fingerprints.append(fields[9].upper())
                primary = False
        if primary_fingerprints != [fingerprint.upper()]:
            raise ValueError('Khóa công khai không khớp fingerprint đã duyệt.')
        command(['gpg', '--batch', '--yes', '--trust-model', 'always', '--compress-algo', 'none',
                 '--cipher-algo', 'AES256', '--recipient', fingerprint, '--output', str(output), '--encrypt', str(bundle)], env=env)


def backup(execute: bool) -> dict:
    if not execute:
        raise ValueError('Chỉ chạy cloud khi có --execute-cloud và môi trường đã được chủ cấp phép.')
    required = ['CLOUDFLARE_ACCOUNT_ID', 'CLOUDFLARE_API_TOKEN', 'D1_DATABASE_ID',
                'R2_BUCKET', 'R2_ENDPOINT_URL', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY',
                'BACKUP_GPG_PUBLIC_KEY', 'BACKUP_GPG_FINGERPRINT']
    if any(not os.environ.get(k) for k in required):
        raise ValueError('Thiếu biến môi trường sao lưu. Xem docs/operations/cloud-backup.md.')
    account, database = os.environ['CLOUDFLARE_ACCOUNT_ID'], os.environ['D1_DATABASE_ID']
    bucket, endpoint = os.environ['R2_BUCKET'], os.environ['R2_ENDPOINT_URL']
    if not re.fullmatch(r'[a-f0-9]{32}', account) or not re.fullmatch(r'[a-fA-F0-9-]{36}', database):
        raise ValueError('Account/database ID không hợp lệ.')
    if not re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', bucket) or endpoint != f'https://{account}.r2.cloudflarestorage.com':
        raise ValueError('Bucket hoặc endpoint R2 không hợp lệ.')
    now = dt.datetime.now(UTC)
    prefix = f'd1-backups/{database}/'
    key = prefix + now.strftime('%Y%m%dT%H%M%SZ') + '.tar.gz.gpg'
    aws = ['aws', '--endpoint-url', endpoint, '--region', 'auto']
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='nt-cloud-backup-') as name:
        folder = Path(name)
        config = folder / 'wrangler.json'
        config.write_text(json.dumps({'name': 'nt-private-backup', 'account_id': account,
            'd1_databases': [{'binding': 'DB', 'database_name': 'backup-target', 'database_id': database}]}), encoding='utf-8')
        sql = folder / 'database.sql'
        command(['npx', '--no-install', 'wrangler', 'd1', 'export', 'backup-target', '--remote', '--skip-confirmation',
                 '--config', str(config), '--output', str(sql)], cwd=ROOT / 'api')
        archive = folder / 'database.tar.gz'
        manifest = make_bundle(sql, archive, now)
        verify_bundle(archive)
        encrypted = folder / 'database.tar.gz.gpg'
        encrypt(archive, encrypted, os.environ['BACKUP_GPG_PUBLIC_KEY'], os.environ['BACKUP_GPG_FINGERPRINT'])
        listed = json.loads(command(aws + ['s3api', 'list-objects-v2', '--bucket', bucket, '--prefix', prefix, '--output', 'json']))
        # This is a bucket budget, not proof of account-wide Free usage. Reserve
        # headroom for other buckets manually; never opt into paid tiers here.
        budget = int(os.environ.get('R2_BACKUP_STORAGE_BUDGET_BYTES', '8000000000'))
        used = sum(int(o['Size']) for o in listed.get('Contents', []))
        if budget <= 0 or used + encrypted.stat().st_size + 128 > budget:
            raise ValueError('Sao lưu vượt ngân sách dung lượng R2 đã cấu hình; không upload hoặc xóa bản cũ.')
        checksum = digest(encrypted)
        sidecar = folder / 'checksum.txt'
        sidecar.write_text(checksum + '\n', encoding='ascii')
        # Do not prune until upload succeeds and HEAD confirms the stored size.
        command(aws + ['s3', 'cp', str(encrypted), f's3://{bucket}/{key}', '--only-show-errors'])
        head = json.loads(command(aws + ['s3api', 'head-object', '--bucket', bucket, '--key', key]))
        if head.get('ContentLength') != encrypted.stat().st_size:
            raise ValueError('Kích thước object không khớp; không xoay vòng backup.')
        # Download and hash the actual R2 ciphertext before pruning. One extra
        # GET; avoids treating a successful upload request as integrity proof.
        downloaded = folder / 'downloaded.gpg'
        command(aws + ['s3', 'cp', f's3://{bucket}/{key}', str(downloaded), '--only-show-errors'])
        if digest(downloaded) != checksum:
            raise ValueError('Checksum object R2 không khớp; không xoay vòng backup.')
        command(aws + ['s3', 'cp', str(sidecar), f's3://{bucket}/{key}.sha256', '--only-show-errors'])
        listed = json.loads(command(aws + ['s3api', 'list-objects-v2', '--bucket', bucket, '--prefix', prefix, '--output', 'json']))
        keys = [o['Key'] for o in listed.get('Contents', [])]
        # AWS CLI automatic pagination remains enabled.
        key_set = set(keys)
        # Incomplete uploads lack sidecars: preserve for investigation rather
        # than using them to evict a known completed backup.
        keep, remove = retention([k for k in keys if k + '.sha256' in key_set], prefix)
        if key not in keep:
            raise ValueError('Backup mới không nằm trong tập giữ lại; không xóa.')
        for expired in sorted(remove):
            payload = folder / 'delete.json'
            payload.write_text(json.dumps({'Objects': [{'Key': expired}, {'Key': expired + '.sha256'}], 'Quiet': True}), encoding='utf-8')
            deleted = json.loads(command(aws + ['s3api', 'delete-objects', '--bucket', bucket, '--delete', 'file://' + str(payload)]))
            if deleted.get('Errors'):
                raise ValueError('Không xoay vòng được object cũ; cần kiểm tra quyền R2.')
        return {'status': 'success', 'created_at': now.isoformat(), 'schema_version': manifest['schema_version'],
                'sql_bytes': manifest['sql_bytes'], 'encrypted_bytes': encrypted.stat().st_size,
                'ciphertext_sha256': checksum, 'local_restore_drill': 'passed',
                'retained_archives': len(keep), 'removed_archives': len(remove),
                'bucket_budget_bytes': budget,
                'storage_before_bytes': used,
                'duration_seconds': round(time.monotonic() - started, 1),
                'd1_export_billing': 'not_measured'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    cloud = sub.add_parser('backup')
    cloud.add_argument('--execute-cloud', action='store_true')
    cloud.add_argument('--report', type=Path)
    drill = sub.add_parser('drill-sql')
    drill.add_argument('sql', type=Path)
    check = sub.add_parser('verify-bundle')
    check.add_argument('archive', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'backup':
            result = backup(args.execute_cloud)
        elif args.action == 'verify-bundle':
            result = verify_bundle(args.archive)
        else:
            with tempfile.TemporaryDirectory(prefix='nt-cloud-restore-') as name:
                result = restore_sql(args.sql, Path(name) / 'restored.sqlite')
        if getattr(args, 'report', None):
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as error:
        # No exception traceback: a failed SQL statement could include salary or
        # credentials. Only fixed messages and exception type reach workflow logs.
        result = {'status': 'failed', 'error_type': type(error).__name__,
                  'message': 'Sao lưu/kiểm chứng thất bại; không công nhận bản mới. Kiểm tra cấu hình và diễn tập trên dữ liệu thử.'}
        if getattr(args, 'report', None):
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result), encoding='utf-8')
        print(json.dumps(result, ensure_ascii=False))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
