import datetime as dt
import io
import json
from pathlib import Path
import sqlite3
import shutil
import os
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import cloud_backup as backup


class CloudBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nt-backup-test-')
        self.folder = Path(self.temp.name)
        self.sql = self.folder / 'fixture.sql'
        con = sqlite3.connect(':memory:')
        for file in sorted((backup.ROOT / 'api/migrations').glob('*.sql')):
            con.executescript(file.read_text(encoding='utf-8'))
        con.executescript("""
INSERT INTO stores VALUES('s1','NT-CN01','Chi nhánh; một',1,'2026-11-17');
INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','2026-11-17');
INSERT INTO users VALUES('u1','fixture','Nhân viên','not-a-real-password','salt',1,0,'2026-11-17');
INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo; trắng','Áo sơ mi','Unisex','Tiểu học','2026–2027','2026-11-17');
INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES('v1','p1','SKU','M','Trắng','cái',50000,100000,'2026-11-17');
INSERT INTO stock_movements VALUES('m1','s1','d1','v1',5,'receipt',NULL,'Tồn đầu','u1','2026-11-17');
""")
        self.sql.write_text('\n'.join(con.iterdump()), encoding='utf-8')
        con.close()

    def tearDown(self):
        self.temp.cleanup()

    def test_actual_schema_restore_integrity_ledger_counts(self):
        report = backup.restore_sql(self.sql, self.folder / 'restored.sqlite')
        self.assertEqual(report['schema_version'], 30)
        self.assertEqual(report['counts']['stock_movements'], 1)
        self.assertEqual(report['stock_ledger'], 'ok')
        with self.assertRaises(ValueError):
            backup.restore_sql(self.sql, self.folder / 'restored.sqlite')

    def test_archive_checkpoint_receipt_roundtrip_and_reject_missing_metadata(self):
        archive_sql = f"""
INSERT INTO audit_archives VALUES('arc','s1','d1',1,1,1,0,'','{'c'*64}','{'a'*64}',10,1,'2026-01-01','u1','fixture/archive','committed','{'b'*64}',20,'2026-01-01','2026-01-01');
INSERT INTO audit_chain_checkpoints VALUES('arc','s1','d1',1,1,1,'{'c'*64}','2026-01-01');
"""
        receipt_sql = f"INSERT INTO audit_archive_receipts VALUES('old-log','s1','d1','arc',1,'{'d'*64}');"
        complete = self.folder / 'archive.sql'
        complete.write_text(self.sql.read_text(encoding='utf-8') + archive_sql + receipt_sql, encoding='utf-8')
        report = backup.restore_sql(complete, self.folder / 'archive.sqlite')
        self.assertEqual(report['audit_archives'], 'ok')
        self.assertEqual(report['counts']['audit_archive_receipts'], 1)
        broken = self.folder / 'missing-receipt.sql'
        broken.write_text(self.sql.read_text(encoding='utf-8') + archive_sql, encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'Archive/checkpoint/receipt'):
            backup.restore_sql(broken, self.folder / 'broken-archive.sqlite')

    def test_roundtrip_bundle_checksum_and_reject_tampering(self):
        target = self.folder / 'backup.tar.gz'
        expected = backup.make_bundle(self.sql, target, dt.datetime(2026, 11, 17, tzinfo=backup.UTC))
        self.assertEqual(backup.verify_bundle(target), expected)
        manifest = {**expected, 'sql_sha256': '0' * 64}
        with tarfile.open(self.folder / 'bad.tar.gz', 'w:gz') as archive:
            archive.add(self.sql, arcname='database.sql')
            data = json.dumps(manifest).encode()
            entry = tarfile.TarInfo('manifest.json')
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
        with self.assertRaisesRegex(ValueError, 'Checksum'):
            backup.verify_bundle(self.folder / 'bad.tar.gz')

    def test_wrong_cache_or_foreign_keys_rejected(self):
        for suffix in ["UPDATE stock_balances SET quantity=99;", "PRAGMA foreign_keys=OFF; INSERT INTO employee_store_assignments VALUES('a1','missing','u1','cashier',1,'2026');"]:
            sql = self.folder / 'bad.sql'
            sql.write_text(self.sql.read_text(encoding='utf-8') + '\n' + suffix, encoding='utf-8')
            with self.assertRaises(ValueError):
                backup.restore_sql(sql, self.folder / (str(len(suffix)) + '.sqlite'))

    def test_no_attach_vacuum_external_or_tar_traversal(self):
        malicious = self.folder / 'attack.sql'
        malicious.write_text("ATTACH DATABASE 'outside.sqlite' AS other;", encoding='utf-8')
        with self.assertRaises(sqlite3.DatabaseError):
            backup.restore_sql(malicious, self.folder / 'attack.sqlite')
        with tarfile.open(self.folder / 'attack.tar.gz', 'w:gz') as archive:
            entry = tarfile.TarInfo('../outside.sql')
            entry.size = 3
            archive.addfile(entry, io.BytesIO(b'bad'))
        with self.assertRaises(ValueError):
            backup.verify_bundle(self.folder / 'attack.tar.gz')

    def test_retention_union_scoped_days_weeks_months(self):
        prefix = 'd1-backups/fixture/'
        keys = [prefix + (dt.datetime(2026, 11, 17) - dt.timedelta(days=i)).strftime('%Y%m%dT%H%M%SZ') + '.tar.gz.gpg' for i in range(800)]
        keep, remove = backup.retention(keys + ['other/20200101T000000Z.tar.gz.gpg', prefix + 'manual.tar.gz.gpg', prefix + '../20200101T000000Z.tar.gz.gpg'], prefix)
        self.assertTrue(set(keys[:30]) <= keep)
        self.assertEqual(keep | remove, set(keys))
        self.assertFalse(keep & remove)
        self.assertTrue(any('202512' in k for k in keep))
        self.assertLess(len(keep), 50)
        with self.assertRaises(ValueError):
            backup.retention(keys, prefix, days=0)

    def test_cloud_requires_explicit_action_without_invoking_tools(self):
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                backup.backup(False)
            command.assert_not_called()

    def transport_fixture(self, *, bad_head=False, budget='8000000000'):
        database = '00000000-0000-0000-0000-000000000001'
        prefix = 'd1-backups/' + database + '/'
        remote = {}
        for i in range(1, 61):
            key = prefix + (dt.datetime.now(backup.UTC) - dt.timedelta(days=i)).strftime('%Y%m%dT%H%M%SZ') + '.tar.gz.gpg'
            remote[key] = b'old-fixture-ciphertext'
            remote[key + '.sha256'] = b'fixture-checksum'
        calls = []

        def command(args, **_):
            calls.append(args)
            if args[0] == 'npx':
                self.assertIn('--remote', args)
                Path(args[args.index('--output') + 1]).write_bytes(self.sql.read_bytes())
                return b''
            if 's3api' in args:
                action = args[args.index('s3api') + 1]
                if action == 'list-objects-v2':
                    return json.dumps({'Contents': [{'Key': k, 'Size': len(v)} for k, v in remote.items()]}).encode()
                if action == 'head-object':
                    key = args[args.index('--key') + 1]
                    return json.dumps({'ContentLength': len(remote[key]) + int(bad_head)}).encode()
                if action == 'delete-objects':
                    path = Path(args[args.index('--delete') + 1].removeprefix('file://'))
                    for row in json.loads(path.read_text(encoding='utf-8'))['Objects']:
                        self.assertTrue(row['Key'].startswith(prefix))
                        remote.pop(row['Key'], None)
                    return b'{}'
            if 's3' in args:
                i = args.index('s3')
                source, target = args[i + 2:i + 4]
                if source.startswith('s3://'):
                    Path(target).write_bytes(remote[source.split('/', 3)[3]])
                else:
                    remote[target.split('/', 3)[3]] = Path(source).read_bytes()
                return b''
            raise AssertionError('Unexpected fixture command')

        env = {'CLOUDFLARE_ACCOUNT_ID': 'a' * 32, 'D1_DATABASE_ID': database,
               'CLOUDFLARE_API_TOKEN': 'fixture-only', 'R2_BUCKET': 'fixture-private',
               'R2_ENDPOINT_URL': 'https://' + 'a' * 32 + '.r2.cloudflarestorage.com',
               'AWS_ACCESS_KEY_ID': 'fixture-only', 'AWS_SECRET_ACCESS_KEY': 'fixture-only',
               'BACKUP_GPG_PUBLIC_KEY': 'fixture-only', 'BACKUP_GPG_FINGERPRINT': 'F' * 40,
               'R2_BACKUP_STORAGE_BUDGET_BYTES': budget}
        return env, remote, calls, command

    def test_mock_cloud_transport_upload_download_checksum_then_retention(self):
        env, remote, calls, command = self.transport_fixture()
        def encrypt(_archive, output, *_):
            output.write_bytes(b'fixture-ciphertext-only')
        with patch.dict(os.environ, env), patch.object(backup, 'command', side_effect=command), patch.object(backup, 'encrypt', side_effect=encrypt):
            report = backup.backup(True)
        self.assertEqual(report['status'], 'success')
        self.assertGreater(report['removed_archives'], 0)
        download = next(i for i, a in enumerate(calls) if 's3' in a and a[a.index('s3') + 2].startswith('s3://'))
        deletion = next(i for i, a in enumerate(calls) if 'delete-objects' in a)
        self.assertLess(download, deletion)

    def test_mock_cloud_bad_head_never_prunes_existing_backup(self):
        env, remote, calls, command = self.transport_fixture(bad_head=True)
        original = set(remote)
        with patch.dict(os.environ, env), patch.object(backup, 'command', side_effect=command), patch.object(backup, 'encrypt', side_effect=lambda _a, out, *_: out.write_bytes(b'fixture-ciphertext')):
            with self.assertRaises(ValueError):
                backup.backup(True)
        self.assertTrue(original <= set(remote))
        self.assertFalse(any('delete-objects' in a for a in calls))

    def test_mock_cloud_storage_budget_blocks_all_r2_writes(self):
        env, remote, calls, command = self.transport_fixture(budget='1')
        original = dict(remote)
        with patch.dict(os.environ, env), patch.object(backup, 'command', side_effect=command), patch.object(backup, 'encrypt', side_effect=lambda _a, out, *_: out.write_bytes(b'fixture-ciphertext')):
            with self.assertRaises(ValueError):
                backup.backup(True)
        self.assertEqual(remote, original)
        self.assertFalse(any('s3' in a or 'delete-objects' in a for a in calls))

    @unittest.skipUnless(shutil.which('gpg'), 'Cần GnuPG để kiểm chứng mã hóa thật.')
    def test_real_public_key_encrypt_decrypt_restore(self):
        home = self.folder / 'gnupg'
        home.mkdir(mode=0o700)
        env = {**os.environ, 'GNUPGHOME': str(home)}
        backup.command(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                        '--quick-generate-key', 'NT backup fixture only', 'rsa2048', 'encr', '1d'], env=env)
        listed = backup.command(['gpg', '--batch', '--with-colons', '--list-keys'], env=env).decode()
        fingerprint = next(line.split(':')[9] for line in listed.splitlines() if line.startswith('fpr:'))
        public = backup.command(['gpg', '--batch', '--armor', '--export', fingerprint], env=env).decode()
        archive, encrypted, decrypted = self.folder / 'actual.tar.gz', self.folder / 'actual.gpg', self.folder / 'decrypted.tar.gz'
        expected = backup.make_bundle(self.sql, archive, dt.datetime.now(backup.UTC))
        backup.encrypt(archive, encrypted, public, fingerprint)
        self.assertNotIn(b'CREATE TABLE', encrypted.read_bytes())
        backup.command(['gpg', '--batch', '--yes', '--output', str(decrypted), '--decrypt', str(encrypted)], env=env)
        self.assertEqual(backup.verify_bundle(decrypted), expected)
        with self.assertRaises(ValueError):
            backup.encrypt(archive, self.folder / 'wrong.gpg', public, 'F' * 40)
        # Stop the isolated agent so Windows can remove the fixture directory.
        backup.command(['gpgconf', '--kill', 'all'], env=env)


if __name__ == '__main__':
    unittest.main()
