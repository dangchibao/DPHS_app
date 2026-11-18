import io
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import cloud_backup as backup
import cloud_restore as restore


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.con = sqlite3.connect(':memory:')
        for file in sorted((backup.ROOT / 'api/migrations').glob('*.sql')):
            self.con.executescript(file.read_text(encoding='utf-8'))
        self.con.executescript("""
INSERT INTO stores VALUES('s1','NT-CN01','Fixture',1,'2026-11-17');
INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Fixture','approved','2026-11-17');
INSERT INTO users VALUES('u1','fixture','Fixture','not-real','salt',1,0,'2026-11-17');
INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Fixture','Ao','Unisex','TH','2026','2026-11-17');
INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES('v1','p1','SKU','M','Trang','cai',50000,100000,'2026-11-17');
INSERT INTO stock_movements VALUES('m1','s1','d1','v1',10,'receipt',NULL,'Fixture','u1','2026-11-17');
INSERT INTO documents VALUES('z-parent','s1','d1','HD','sale','HD-fixture','2026-11-17','u1',NULL,NULL,0,0,0,'2026','{}');
INSERT INTO documents VALUES('a-child','s1','d1','DT','exchange','DT-fixture','2026-11-17','u1',NULL,'z-parent',0,0,0,'2026','{}');
INSERT INTO document_counters VALUES('s1','d1','HD','20261117',9007199254740993);
DELETE FROM sqlite_sequence WHERE name='change_feed';
INSERT INTO sqlite_sequence VALUES('change_feed',9999);
""")
        self.large = 'Tiếng Việt; ' * 15000 + "'); DROP TABLE users; --"
        self.blob = bytes(range(256)) * 800
        self.con.execute('INSERT INTO store_settings VALUES(?,?,?)', ('s1', 'fixture', self.large))
        self.con.execute('INSERT INTO media_cache VALUES(?,?,?)', ('fixture', self.blob, '2026-11-17'))
        self.con.commit()

    def tearDown(self):
        self.con.close()

    def source(self):
        counts = {name: self.con.execute('SELECT COUNT(*) FROM ' + backup.quote(name)).fetchone()[0]
                  for (kind, name) in restore.schema(self.con) if kind == 'table'}
        return restore.Source(self.con, {'schema_version': 30, 'counts': counts})

    def test_large_rows_blob_int64_fk_and_caches_restore_without_large_sql(self):
        source = self.source()
        target = sqlite3.connect(':memory:')
        target.execute('PRAGMA foreign_keys=ON')
        self.addCleanup(target.close)
        local = restore.LocalTransport(target)
        statements = []

        def transport(queries):
            statements.extend(queries)
            for query in queries:
                self.assertLess(len(query['sql'].encode()), restore.MAX_SQL_BYTES)
                self.assertLessEqual(len(query.get('params', [])), 100)
                self.assertTrue(all(isinstance(p, str) for p in query.get('params', [])))
            return local(queries)

        result = restore.execute(source, transport)
        self.assertEqual(result['table_checksums'], 'ok')
        self.assertEqual(target.execute('SELECT value FROM document_counters').fetchone()[0], 9007199254740993)
        self.assertEqual(target.execute('SELECT value FROM store_settings').fetchone()[0], self.large)
        self.assertEqual(target.execute('SELECT content FROM media_cache').fetchone()[0], self.blob)
        self.assertEqual(target.execute('SELECT quantity FROM stock_balances').fetchone()[0], 10)
        self.assertEqual(target.execute('SELECT seq FROM sqlite_sequence WHERE name=?', ('change_feed',)).fetchone()[0], 9999)
        self.assertTrue(any(any(len(v) > 100000 for v in q.get('params', [])) for q in statements))
        target.execute("INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES('s1','next','fixture','x','{}','2026')")
        self.assertEqual(target.execute('SELECT server_seq FROM change_feed').fetchone()[0], 10000)

    def test_untrusted_schema_and_document_cycle_rejected_before_transport(self):
        self.con.executescript('CREATE TRIGGER untrusted AFTER INSERT ON users BEGIN DELETE FROM products; END;')
        with self.assertRaisesRegex(ValueError, 'Schema backup khác'):
            self.source()
        original=self.con.execute("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='documents_no_update'").fetchone()[0]
        self.con.executescript('DROP TRIGGER untrusted; DROP TRIGGER documents_no_update;')
        self.con.execute("UPDATE documents SET original_id='a-child' WHERE id='z-parent'")
        self.con.execute(original)
        with self.assertRaisesRegex(ValueError, 'chu kỳ'):
            self.source()

    def test_write_budget_and_nonempty_target_refuse_before_writes(self):
        source = self.source()
        called = []
        with self.assertRaisesRegex(ValueError, 'ngân sách'):
            restore.execute(source, lambda queries: called.append(queries), write_budget=1)
        self.assertEqual(called, [])
        target = sqlite3.connect(':memory:')
        self.addCleanup(target.close)
        target.execute('CREATE TABLE real_data(id TEXT)')
        target.execute("INSERT INTO real_data VALUES('keep')")
        with self.assertRaisesRegex(ValueError, 'Target không trống'):
            restore.execute(source, restore.LocalTransport(target))
        self.assertEqual(target.execute('SELECT id FROM real_data').fetchone()[0], 'keep')

    def test_uncertain_write_aborts_without_retry_or_target_activation(self):
        source = self.source()
        target = sqlite3.connect(':memory:')
        self.addCleanup(target.close)
        local = restore.LocalTransport(target)
        lost = []

        def failing(queries):
            result = local(queries)
            if any(q['sql'].startswith('INSERT INTO') for q in queries):
                lost.append(True)
                raise ValueError('Lost ACK')
            return result

        with self.assertRaisesRegex(ValueError, 'Lost ACK'):
            restore.execute(source, failing)
        self.assertEqual(len(lost), 1)

    def test_target_checksum_mismatch_is_not_accepted(self):
        source = self.source()
        target = sqlite3.connect(':memory:')
        self.addCleanup(target.close)
        local = restore.LocalTransport(target)
        changed = []

        def transport(queries):
            result = local(queries)
            if not changed and any(q['sql'].startswith('CREATE TRIGGER') for q in queries):
                target.execute('UPDATE stock_balances SET quantity=11')
                target.commit()
                changed.append(True)
            return result

        with self.assertRaisesRegex(ValueError, 'count/checksum'):
            restore.execute(source, transport)

    def test_verified_backup_bundle_drills_without_cloud_credentials(self):
        with tempfile.TemporaryDirectory(prefix='nt-restore-bundle-') as folder:
            sql, bundle = Path(folder) / 'source.sql', Path(folder) / 'backup.tar.gz'
            sql.write_text('\n'.join(self.con.iterdump()), encoding='utf-8')
            backup.make_bundle(sql, bundle, dt.datetime(2026, 11, 17, tzinfo=backup.UTC))
            output = io.StringIO()
            with patch('sys.stdout', output), patch.object(restore, 'CloudTransport') as cloud:
                restore.main([str(bundle), '--bundle'])
                cloud.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())['status'], 'local_drill_verified')

    def test_same_production_uuid_rejected_without_cloud_transport(self):
        with tempfile.TemporaryDirectory(prefix='nt-restore-test-') as folder:
            sql = Path(folder) / 'source.sql'
            sql.write_text('\n'.join(self.con.iterdump()), encoding='utf-8')
            same = '00000000-0000-0000-0000-000000000001'
            with patch.dict(os.environ, {'D1_RESTORE_TARGET_ID': same, 'D1_DATABASE_ID': same}), patch.object(restore, 'CloudTransport') as cloud:
                with self.assertRaisesRegex(ValueError, 'khác database'):
                    restore.main([str(sql), '--execute-cloud', '--confirm-empty-target', same])
                cloud.assert_not_called()

    def test_rest_batches_use_official_endpoint_string_binds_no_redirect_or_error_echo(self):
        requests = []

        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                batch = json.loads(request.data)['batch']
                return io.BytesIO(json.dumps({'success': True, 'result': [{'success': True, 'results': []} for _ in batch]}).encode())

        with patch.object(restore.urllib.request, 'build_opener', return_value=Opener()), patch.object(restore.time, 'sleep'):
            client = restore.CloudTransport('a' * 32, '00000000-0000-0000-0000-000000000002', 'fixture-token')
            self.assertEqual(client([{'sql': 'SELECT ?', 'params': ['9007199254740993']}]), [[]])
        self.assertTrue(requests[0].full_url.startswith('https://api.cloudflare.com/client/v4/accounts/'))
        self.assertEqual(json.loads(requests[0].data)['batch'][0]['params'], ['9007199254740993'])
        with self.assertRaisesRegex(ValueError, 'redirect'):
            restore.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://untrusted.test')


if __name__ == '__main__':
    unittest.main()
