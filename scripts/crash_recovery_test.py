"""Kill only our Flutter test process tree; all sales use a new temporary SQLite DB."""
import os
from contextlib import closing
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    flutter = shutil.which('flutter') or shutil.which('flutter.bat') or r'D:\development\flutter\bin\flutter.bat'
    with tempfile.TemporaryDirectory(prefix='nt-pos-crash-') as folder:
        db = Path(folder) / 'pos.sqlite'
        marker = Path(str(db) + '.ready')
        for phase in ('before', 'after', 'recover'):
            env = {**os.environ, 'NT_CRASH_DB': str(db), 'NT_CRASH_PHASE': phase}
            command = [flutter, 'test', 'test/integration/crash_recovery_worker.dart', '--reporter', 'expanded']
            # Windows BAT needs cmd.exe; no user-controlled arguments are interpolated.
            if os.name == 'nt':
                command = [os.environ.get('COMSPEC', 'cmd.exe'), '/d', '/s', '/c', subprocess.list2cmdline(command)]
            log = Path(folder) / f'{phase}.log'
            with log.open('wb') as stream:
                process = subprocess.Popen(command, cwd=ROOT / 'app', env=env, stdout=stream, stderr=subprocess.STDOUT,
                                           start_new_session=os.name != 'nt')
                try:
                    deadline = time.monotonic() + 180
                    if phase == 'recover':
                        code = process.wait(timeout=180)
                        if code:
                            raise RuntimeError(log.read_text(encoding='utf-8', errors='replace'))
                    else:
                        while not marker.exists():
                            if process.poll() is not None or time.monotonic() > deadline:
                                raise RuntimeError(log.read_text(encoding='utf-8', errors='replace'))
                            time.sleep(.1)
                        if marker.read_text() != phase:
                            raise RuntimeError('Unexpected fixture checkpoint')
                finally:
                    if process.poll() is None:
                        if os.name == 'nt':
                            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], check=True, capture_output=True)
                        else:
                            os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=30)
            marker.unlink(missing_ok=True)
            with closing(sqlite3.connect(db)) as connection:
                assert connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
                count = connection.execute('SELECT COUNT(*) FROM documents').fetchone()[0]
                assert count == {'before': 0, 'after': 1, 'recover': 2}[phase]
                assert connection.execute("SELECT COUNT(*) FROM audit_logs WHERE action='INVOICE_CREATE'").fetchone()[0] == count
                assert connection.execute("SELECT COUNT(*) FROM outbox WHERE entity_type='sale'").fetchone()[0] == count
                assert connection.execute("SELECT quantity FROM stock_balances").fetchone()[0] == 10-count
                counter = connection.execute('SELECT value FROM document_counters').fetchall()
                assert counter == ([] if not count else [(count,)])
            print(f'PASS {phase}: SQLite integrity and {count} committed invoice(s)', flush=True)
    print('PASS: process kill before/after commit, counter continuity, replay, stock, audit/outbox transaction.')


if __name__ == '__main__':
    main()
