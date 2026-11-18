"""Verified SQL -> empty, unbound D1 using bound parameters, never production.

Default is a local SQLite drill of the exact generated requests. Cloud execution
requires two explicit flags and environment credentials. Failed imports stay
quarantined in their new target; this tool never binds, deploys or deletes a DB.
"""
from __future__ import annotations
import argparse
from contextlib import closing
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import tarfile
import shutil
import tempfile
import time
import urllib.error
import urllib.request
import cloud_backup as backup

MAX_SQL_BYTES = 95000
MAX_PARAMS = 100
MAX_BATCH_ROWS = 25
MAX_BATCH_BYTES = 1000000
MAX_SINGLE_BYTES = 16000000
DEFAULT_WRITE_BUDGET = 80000
UUID = re.compile(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', re.I)
TOKEN = re.compile(r"'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|--[^\n]*|/\*.*?\*/|[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?|[^\s]", re.S)


def normalized(sql):
    result = []
    for part in TOKEN.findall(sql):
        if part.startswith(('--', '/*')):
            continue
        if part.startswith("'"):
            result.append(part)
        elif part.startswith('"'):
            name = part[1:-1].replace('""', '"')
            result.append(name.lower() if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name) else part)
        else:
            result.append(part.lower())
    return '|'.join(result).rstrip('|;')


def schema(con):
    return {(kind, name): sql for kind, name, sql in con.execute(
        "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND type IN ('table','index','view','trigger')")
        if not name.startswith(('sqlite_', '_cf_'))}


def verify_project_schema(con, version):
    files = sorted((backup.ROOT / 'api/migrations').glob('*.sql'))
    if version < 1 or version > len(files):
        raise ValueError('Phiên bản schema chưa được công cụ hỗ trợ.')
    if [r[0] for r in con.execute('SELECT version FROM schema_metadata ORDER BY version')] != list(range(1,version+1)):
        raise ValueError('Lịch sử migration không đầy đủ.')
    with closing(sqlite3.connect(':memory:')) as expected:
        for file in files[:version]:
            expected.executescript(file.read_text(encoding='utf-8'))
        actual, wanted = schema(con), schema(expected)
        metadata = actual.pop(('table', 'd1_migrations'), None)
        if metadata:
            names = [r[1] for r in con.execute('PRAGMA table_info(d1_migrations)')]
            if names != ['id', 'name', 'applied_at']:
                raise ValueError('Metadata Wrangler không đúng cấu trúc.')
            allowed = {f.name for f in files[:version]}
            if any(name not in allowed for name, in con.execute('SELECT name FROM d1_migrations')):
                raise ValueError('Metadata chứa migration không được hỗ trợ.')
        if {key: normalized(value) for key, value in actual.items()} != {key: normalized(value) for key, value in wanted.items()}:
            raise ValueError('Schema backup khác migration đã kiểm chứng; không chạy SQL cloud.')


def binding(value):
    # REST params are strings. Explicit casts preserve int64, NULL and BLOB.
    if value is None:
        return 'NULL', []
    if isinstance(value, bytes):
        return 'unhex(?)', [value.hex()]
    if isinstance(value, int):
        return 'CAST(? AS INTEGER)', [str(value)]
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError('Không hỗ trợ NaN/Infinity.')
        return 'CAST(? AS REAL)', [repr(value)]
    if isinstance(value, str):
        return '?', [value]
    raise ValueError('Kiểu dữ liệu không được hỗ trợ.')


def insertion(table, columns, row):
    terms, params = [], []
    for value in row:
        term, bound = binding(value)
        terms.append(term)
        params.extend(bound)
    sql = f'INSERT INTO {backup.quote(table)}({",".join(map(backup.quote, columns))}) VALUES({",".join(terms)})'
    if len(params) > MAX_PARAMS or len(sql.encode()) > MAX_SQL_BYTES:
        raise ValueError('Statement vượt giới hạn SQL/bind.')
    query = {'sql': sql, 'params': params}
    if len(json.dumps(query, ensure_ascii=False).encode()) > MAX_SINGLE_BYTES:
        raise ValueError('Một hàng vượt ngân sách request an toàn.')
    return query


class Source:
    def __init__(self, con, report):
        self.con, self.report = con, report
        verify_project_schema(con, report['schema_version'])
        self.objects = schema(con)
        self.tables = {name: sql for (kind, name), sql in self.objects.items() if kind == 'table'}
        self.info = {name: list(con.execute('PRAGMA table_info(' + backup.quote(name) + ')')) for name in self.tables}
        self.columns = {name: [r[1] for r in info] for name, info in self.info.items()}
        self.keys = {name: [r[1] for r in sorted(info, key=lambda r: r[5]) if r[5]] for name, info in self.info.items()}
        self.self_refs = {}
        dependencies = {}
        for name in self.tables:
            if not self.keys[name]:
                raise ValueError('Bảng thiếu primary key: ' + name)
            fks = list(con.execute('PRAGMA foreign_key_list(' + backup.quote(name) + ')'))
            dependencies[name] = {r[2] for r in fks if r[2] != name}
            own = [r for r in fks if r[2] == name]
            if own:
                if len(own) != 1 or len(self.keys[name]) != 1 or own[0][4] != self.keys[name][0]:
                    raise ValueError('Self-reference cần quy trình riêng: ' + name)
                self.self_refs[name] = (own[0][3], own[0][4])
                parent, key = self.self_refs[name]
                tree = self.tree(name, parent, key)
                reached, depth = con.execute(tree + ' SELECT COUNT(*),COALESCE(MAX(depth),0) FROM restore_tree').fetchone()
                if reached != report['counts'][name] or depth > 1000:
                    raise ValueError('Self-reference có chu kỳ hoặc quá sâu: ' + name)
        self.order = []
        todo = dict(dependencies)
        while todo:
            ready = sorted(name for name, parents in todo.items() if not parents.intersection(todo))
            if not ready:
                raise ValueError('Chu kỳ foreign key giữa các bảng; chưa ghi cloud.')
            for name in ready:
                self.order.append(name)
                del todo[name]
        self.meta, self.has_blob = {}, False
        for name in self.order:
            if con.execute('SELECT 1 FROM ' + backup.quote(name) + ' WHERE ' + ' OR '.join(backup.quote(k) + " IS NULL OR typeof(" + backup.quote(k) + ") NOT IN ('integer','text')" for k in self.keys[name]) + ' LIMIT 1').fetchone():
                raise ValueError('Primary key NULL không được khôi phục: ' + name)
            digest, max_bytes = hashlib.sha256(), 1
            for row in con.execute(self.projection(name) + self.order_clause(name)):
                encoded = self.encoded(row)
                digest.update(encoded + b'\n')
                max_bytes = max(max_bytes, len(encoded))
                self.has_blob |= 'blob' in row[::2]
            self.meta[name] = {'sha256': digest.hexdigest(), 'rows': report['counts'][name], 'page_rows': max(1, min(100, 500000 // max_bytes))}
            # Preflight every generated insertion before any cloud operation.
            for row in self.rows(name):
                insertion(name, self.columns[name], row)
        self.writes = sum(report['counts'][name] for name in self.tables)
        for name in self.tables:
            for index in con.execute('PRAGMA index_list(' + backup.quote(name) + ')'):
                definition = con.execute('SELECT sql FROM sqlite_master WHERE type=? AND name=?', ('index', index[1])).fetchone()[0]
                where = re.split(r'\bWHERE\b', definition, flags=re.I)[1] if definition and re.search(r'\bWHERE\b', definition, re.I) else ''
                self.writes += con.execute('SELECT COUNT(*) FROM ' + backup.quote(name) + (' WHERE ' + where if where else '')).fetchone()[0]
        sequence_count=con.execute('SELECT COUNT(*) FROM sqlite_sequence').fetchone()[0] if con.execute("SELECT 1 FROM sqlite_master WHERE name='sqlite_sequence'").fetchone() else 0
        self.writes += len(self.objects) + sequence_count*2
        for value in self.objects.values():
            if len(value.encode()) > MAX_SQL_BYTES:
                raise ValueError('DDL vượt giới hạn câu SQL.')

    @staticmethod
    def tree(name, parent, key):
        table, p, k = map(backup.quote, (name, parent, key))
        return f'WITH RECURSIVE restore_tree(pk,depth) AS (SELECT {k},0 FROM {table} WHERE {p} IS NULL UNION ALL SELECT d.{k},t.depth+1 FROM {table} d JOIN restore_tree t ON d.{p}=t.pk)'

    def rows(self, name):
        table = backup.quote(name)
        if name in self.self_refs:
            parent, key = self.self_refs[name]
            return self.con.execute(self.tree(name, parent, key) + f' SELECT {",".join("d."+backup.quote(c) for c in self.columns[name])} FROM {table} d JOIN restore_tree t ON d.{backup.quote(key)}=t.pk ORDER BY t.depth,d.{backup.quote(key)}')
        return self.con.execute('SELECT ' + ','.join(map(backup.quote, self.columns[name])) + ' FROM ' + table + self.order_clause(name))

    def order_clause(self, name):
        return ' ORDER BY ' + ','.join(map(backup.quote, self.keys[name]))

    def projection(self, name):
        fields = []
        for i, col in enumerate(self.columns[name]):
            q = backup.quote(col)
            fields.extend([f'typeof({q}) AS t{i}', f"CASE typeof({q}) WHEN 'blob' THEN hex({q}) WHEN 'integer' THEN CAST({q} AS TEXT) WHEN 'real' THEN printf('%!.17g',{q}) ELSE {q} END AS v{i}"])
        return 'SELECT ' + ','.join(fields) + ' FROM ' + backup.quote(name)

    @staticmethod
    def encoded(row):
        return json.dumps(list(row), ensure_ascii=False, separators=(',', ':')).encode()


class LocalTransport:
    def __init__(self, con):
        self.con = con

    def __call__(self, queries):
        results = []
        with self.con:
            for query in queries:
                cursor = self.con.execute(query['sql'], query.get('params', []))
                columns = [r[0] for r in cursor.description] if cursor.description else []
                results.append([dict(zip(columns, row)) for row in cursor.fetchall()])
        return results


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('API redirect không được phép.')


class CloudTransport:
    def __init__(self, account, target, token):
        if not re.fullmatch('[a-fA-F0-9]{32}', account) or not UUID.fullmatch(target) or not token:
            raise ValueError('Cấu hình tài khoản/target/token không hợp lệ.')
        self.url = f'https://api.cloudflare.com/client/v4/accounts/{account}/d1/database/{target}/query'
        self.token = token
        self.open = urllib.request.build_opener(NoRedirect())
        self.last = 0.0

    def __call__(self, queries):
        time.sleep(max(0, .35 - (time.monotonic() - self.last)))
        payload = json.dumps({'batch': queries}, ensure_ascii=False).encode()
        request = urllib.request.Request(self.url, data=payload, headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'})
        try:
            with self.open.open(request, timeout=30) as response:
                data = response.read(MAX_SINGLE_BYTES + 1)
        except urllib.error.HTTPError as error:
            raise ValueError(f'D1 HTTP {error.code}; không retry ghi và không tự kích hoạt target.') from None
        except (OSError, TimeoutError):
            raise ValueError('Mất phản hồi D1; target có thể nhập dở. Không dùng target này trước đối soát.') from None
        finally:
            self.last = time.monotonic()
        if len(data) > MAX_SINGLE_BYTES:
            raise ValueError('D1 trả kết quả quá lớn.')
        try:
            body = json.loads(data)
        except (ValueError, TypeError):
            raise ValueError('Phản hồi D1 không hợp lệ.') from None
        if body.get('success') is not True or len(body.get('result', [])) != len(queries) or any(r.get('success') is not True for r in body['result']):
            raise ValueError('D1 không xác nhận toàn bộ lô. Không tự retry hoặc sử dụng target nhập dở.')
        return [r.get('results', []) for r in body['result']]


def execute(source, transport, write_budget=DEFAULT_WRITE_BUDGET):
    if source.writes > write_budget:
        raise ValueError(f'Ước tính {source.writes} lượt ghi vượt ngân sách phục hồi {write_budget}; chưa ghi target.')
    objects = transport([{'sql': "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND substr(name,1,7)<>'sqlite_' AND substr(name,1,4)<>'_cf_'"}])[0]
    if any(r['name'] != 'd1_migrations' or r['type'] != 'table' for r in objects):
        raise ValueError('Target không trống. Không khôi phục đè dữ liệu.')
    metadata_exists = bool(objects)
    if metadata_exists and (('table','d1_migrations') not in source.objects or normalized(objects[0]['sql']) != normalized(source.objects[('table','d1_migrations')])):
        raise ValueError('Metadata target khác backup. Cần database mới hoàn toàn.')
    if metadata_exists and transport([{'sql': 'SELECT COUNT(*) n FROM d1_migrations'}])[0][0]['n'] != 0:
        raise ValueError('Target đã có migration. Cần database mới chưa sử dụng.')
    if source.has_blob and transport([{'sql': "SELECT hex(unhex('00FF')) AS value"}])[0][0].get('value') != '00FF':
        raise ValueError('D1 chưa hỗ trợ bind BLOB bằng unhex; target chưa được ghi.')
    requests = 0

    def send(queries):
        nonlocal requests
        if queries:
            transport(queries)
            requests += 1

    # Triggers install after rows: replaying derived caches must not add stock twice.
    ddls = [source.tables[name] for name in source.order if not (metadata_exists and name == 'd1_migrations')]
    ddls += [sql for (kind, _), sql in source.objects.items() if kind == 'index']
    for offset in range(0, len(ddls), MAX_BATCH_ROWS):
        send([{'sql': sql} for sql in ddls[offset:offset + MAX_BATCH_ROWS]])
    for name in source.order:
        batch, size = [], 0
        for row in source.rows(name):
            query = insertion(name, source.columns[name], row)
            length = len(json.dumps(query, ensure_ascii=False).encode())
            if batch and (len(batch) >= MAX_BATCH_ROWS or size + length > MAX_BATCH_BYTES):
                send(batch)
                batch, size = [], 0
            batch.append(query)
            size += length
        send(batch)
    sequences = source.con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'").fetchone()
    if sequences:
        # Preserve cursor high-water marks even if the latest feed rows were archived.
        for name, seq in source.con.execute('SELECT name,seq FROM sqlite_sequence'):
            send([{'sql': 'DELETE FROM sqlite_sequence WHERE name=?', 'params': [name]},
                  {'sql': 'INSERT INTO sqlite_sequence(name,seq) VALUES(?,CAST(? AS INTEGER))', 'params': [name, str(seq)]}])
    tail = [sql for (kind, _), sql in source.objects.items() if kind in ('view', 'trigger')]
    for offset in range(0, len(tail), MAX_BATCH_ROWS):
        send([{'sql': sql} for sql in tail[offset:offset + MAX_BATCH_ROWS]])
    for name in source.order:
        digest, count, cursor = hashlib.sha256(), 0, None
        while True:
            sql, params = source.projection(name), []
            if cursor is not None:
                terms = []
                for value in cursor:
                    term, bound = binding(value)
                    terms.append(term)
                    params.extend(bound)
                sql += ' WHERE (' + ','.join(map(backup.quote, source.keys[name])) + ')>(' + ','.join(terms) + ')'
            sql += source.order_clause(name) + ' LIMIT ' + str(source.meta[name]['page_rows'])
            rows = transport([{'sql': sql, 'params': params}])[0]
            if not rows:
                break
            for row in rows:
                pairs = [row[key] for i in range(len(source.columns[name])) for key in (f't{i}', f'v{i}')]
                digest.update(source.encoded(pairs) + b'\n')
                count += 1
            cursor = []
            for key in source.keys[name]:
                i = source.columns[name].index(key)
                kind, value = rows[-1][f't{i}'], rows[-1][f'v{i}']
                if kind not in ('text', 'integer'):
                    raise ValueError('Primary key không hỗ trợ keyset: ' + name)
                cursor.append(int(value) if kind == 'integer' else value)
        if count != source.meta[name]['rows'] or digest.hexdigest() != source.meta[name]['sha256']:
            raise ValueError('Dữ liệu target sai count/checksum: ' + name)
    actual = transport([{'sql': "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND substr(name,1,7)<>'sqlite_' AND substr(name,1,4)<>'_cf_'"}])[0]
    if {(r['type'], r['name']): normalized(r['sql']) for r in actual} != {k: normalized(v) for k, v in source.objects.items()}:
        raise ValueError('Schema target không khớp backup.')
    if transport([{'sql': 'PRAGMA foreign_key_check'}])[0]:
        raise ValueError('Foreign key target không hợp lệ.')
    integrity = transport([{'sql': 'PRAGMA quick_check'}])[0]
    if len(integrity) != 1 or list(integrity[0].values()) != ['ok']:
        raise ValueError('Integrity target không hợp lệ.')
    return {'status': 'verified_unbound_target', 'schema_version': source.report['schema_version'],
            'tables': len(source.order), 'rows': sum(m['rows'] for m in source.meta.values()),
            'estimated_writes': source.writes, 'write_requests': requests, 'integrity': 'quick_check_ok',
            'foreign_keys': 'ok', 'table_checksums': 'ok', 'deployed': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sql', type=Path)
    parser.add_argument('--bundle', action='store_true', help='Đầu vào là tar.gz đã giải mã; kiểm tra checksum trước khi lấy SQL.')
    parser.add_argument('--execute-cloud', action='store_true')
    parser.add_argument('--confirm-empty-target')
    parser.add_argument('--write-budget', type=int, default=DEFAULT_WRITE_BUDGET)
    args = parser.parse_args(argv)
    if args.write_budget < 1:
        raise ValueError('Ngân sách ghi phải dương.')
    with tempfile.TemporaryDirectory(prefix='nt-cloud-restore-') as temporary:
        folder = Path(temporary)
        source_sql=args.sql
        if args.bundle:
            backup.verify_bundle(args.sql)
            source_sql=folder/'database.sql'
            with tarfile.open(args.sql,'r:gz') as bundle, bundle.extractfile('database.sql') as stream, source_sql.open('wb') as output:
                shutil.copyfileobj(stream,output)
        report = backup.restore_sql(source_sql, folder / 'source.sqlite')
        with closing(sqlite3.connect(folder / 'source.sqlite')) as con:
            source = Source(con, report)
            if args.execute_cloud:
                target, original = os.environ.get('D1_RESTORE_TARGET_ID', ''), os.environ.get('D1_DATABASE_ID', '')
                if not UUID.fullmatch(original) or not UUID.fullmatch(target) or target.lower() == original.lower() or args.confirm_empty_target != target:
                    raise ValueError('Cần xác nhận đúng UUID target mới và khác database nguồn/production.')
                transport = CloudTransport(os.environ.get('CLOUDFLARE_ACCOUNT_ID', ''), target, os.environ.get('D1_RESTORE_API_TOKEN', ''))
                result = execute(source, transport, args.write_budget)
            else:
                with closing(sqlite3.connect(folder / 'drill.sqlite')) as destination:
                    destination.execute('PRAGMA foreign_keys=ON')
                    result = execute(source, LocalTransport(destination), args.write_budget)
                result['status'] = 'local_drill_verified'
            print(json.dumps({**result, 'source_sql_sha256': backup.digest(source_sql)}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, sqlite3.Error) as error:
        # Never print SQL, bind values, token, HTTP error body or source rows.
        if isinstance(error, sqlite3.Error):
            raise SystemExit('SQLite staging không đạt; không kích hoạt target.') from None
        raise SystemExit(str(error)) from None
