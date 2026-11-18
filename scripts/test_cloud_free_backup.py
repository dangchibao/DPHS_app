import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import cloud_backup as backup
import free_d1_backup as free
import test_cloud_backup as fixtures
import verify_free_backup as restore


class FreeLocalBackupTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.CloudBackupTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.folder = self.fixture.folder
        self.destination = self.folder / 'backups'
        self.database = '12345678-1234-1234-1234-123456789abc'
        self.config = self.folder / 'config.json'
        self.config.write_text(json.dumps({'account_id': 'a' * 32, 'd1_databases': [
            {'binding': 'DB', 'database_id': self.database}]}), encoding='utf-8')
        self.public = self.folder / 'public.asc'
        self.public.write_text('fixture-public-key', encoding='utf-8')
        self.calls = []

    def export(self, args, **kwargs):
        self.calls.append(args)
        self.assertIn('export', args)
        self.assertNotIn('aws', args)
        self.assertNotIn('r2', args)
        Path(args[args.index('--output') + 1]).write_bytes(self.fixture.sql.read_bytes())
        return b''

    def encrypt(self, source, target, *_):
        # Actual GPG roundtrip is separately exercised by test_cloud_backup and
        # the owner-key drill. This isolates file commit and failure semantics.
        self.assertTrue(source.exists())
        target.write_bytes(b'fixture-encrypted-content')

    def run_backup(self, **kwargs):
        return free.run(self.config, self.destination, self.public, 'A' * 40,
                        execute=True, **kwargs)

    def test_no_export_without_explicit_execute(self):
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                free.run(self.config, self.destination, self.public, 'A' * 40)
            command.assert_not_called()
        self.assertFalse(self.destination.exists())

    def test_export_restore_encrypt_readback_and_completion_marker_no_plaintext(self):
        with patch.object(backup, 'command', side_effect=self.export), patch.object(backup, 'encrypt', side_effect=self.encrypt):
            result = self.run_backup()
        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['schema_version'], 30)
        self.assertFalse(result['r2_used'])
        self.assertEqual(len(self.calls), 1)
        encrypted = Path(result['encrypted_file'])
        self.assertEqual(backup.digest(encrypted), Path(str(encrypted) + '.sha256').read_text().strip())
        self.assertEqual({p.name for p in encrypted.parent.iterdir()}, {encrypted.name, encrypted.name + '.sha256'})

    def test_budget_preserves_old_backup_and_blocks_export(self):
        folder = self.destination / self.database
        folder.mkdir(parents=True)
        old = folder / 'old.gpg'
        old.write_bytes(b'old-ciphertext')
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                self.run_backup(budget=1)
            command.assert_not_called()
        self.assertEqual(old.read_bytes(), b'old-ciphertext')

    def test_existing_lock_is_preserved_and_blocks_overlap(self):
        folder = self.destination / self.database
        folder.mkdir(parents=True)
        lock = folder / '.backup.lock'
        lock.write_bytes(b'other-run')
        with patch.object(backup, 'command') as command:
            with self.assertRaises(FileExistsError):
                self.run_backup()
            command.assert_not_called()
        self.assertEqual(lock.read_bytes(), b'other-run')

    def test_corrupt_export_never_gets_completion_marker(self):
        self.fixture.sql.write_text('not valid sql', encoding='utf-8')
        with patch.object(backup, 'command', side_effect=self.export), patch.object(backup, 'encrypt') as encrypt:
            with self.assertRaises(Exception):
                self.run_backup()
            encrypt.assert_not_called()
        self.assertEqual(list((self.destination / self.database).iterdir()), [])

    def test_encrypt_failure_removes_only_own_temporary_files(self):
        folder = self.destination / self.database
        folder.mkdir(parents=True)
        old = folder / 'old.gpg'
        old.write_bytes(b'old')
        with patch.object(backup, 'command', side_effect=self.export), patch.object(backup, 'encrypt', side_effect=RuntimeError('fixture')):
            with self.assertRaises(RuntimeError):
                self.run_backup()
        self.assertEqual(list(folder.iterdir()), [old])

    def test_readback_failure_never_marks_backup_complete(self):
        original_digest = backup.digest
        def digest(path):
            if path.parent == self.destination / self.database:
                return 'wrong-checksum'
            return original_digest(path)
        with patch.object(backup, 'command', side_effect=self.export), patch.object(backup, 'encrypt', side_effect=self.encrypt), patch.object(backup, 'digest', side_effect=digest):
            with self.assertRaises(ValueError):
                self.run_backup()
        folder = self.destination / self.database
        self.assertEqual(len(list(folder.glob('*.gpg'))), 1)
        self.assertEqual(list(folder.glob('*.sha256')), [])
        self.assertFalse((folder / '.backup.lock').exists())

    def test_repo_destination_and_invalid_config_never_export(self):
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                free.run(self.config, backup.ROOT / 'artifacts/not-allowed', self.public, 'A' * 40, execute=True)
            self.config.write_text('{"d1_databases": []}', encoding='utf-8')
            with self.assertRaises(ValueError):
                self.run_backup()
            command.assert_not_called()

    def test_restore_drill_requires_passphrase_without_invoking_gpg(self):
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                restore.verify(self.folder / 'missing.json', self.folder / 'private.asc', None)
            command.assert_not_called()

    def test_restore_drill_rejects_failed_backup_before_accessing_private_key(self):
        report = self.folder / 'report.json'
        report.write_text('{"status":"failed"}', encoding='utf-8')
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                restore.verify(report, self.folder / 'private.asc', 'fixture-password')
            command.assert_not_called()

    def test_restore_drill_rejects_tampered_ciphertext_before_accessing_private_key(self):
        cipher = self.folder / 'backup.gpg'
        cipher.write_bytes(b'tampered')
        report = self.folder / 'report.json'
        report.write_text(json.dumps({'status': 'success', 'mode': 'local_encrypted_no_r2',
                                     'encrypted_file': str(cipher), 'ciphertext_sha256': 'a' * 64}), encoding='utf-8')
        with patch.object(backup, 'command') as command:
            with self.assertRaises(ValueError):
                restore.verify(report, self.folder / 'private.asc', 'fixture-password')
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
