import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import prepare_backup_key as keys


class OwnerKeyGuards(unittest.TestCase):
    def test_missing_passphrase_has_no_side_effects(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {'NT_BACKUP_KEY_PASSPHRASE': ''}):
            folder = Path(name)
            with self.assertRaises(ValueError), patch.object(keys.backup, 'command', side_effect=AssertionError('GPG must not run')):
                keys.prepare(folder, create=True)
            self.assertEqual(list(folder.iterdir()), [])

    def test_generation_requires_explicit_flag(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {'NT_BACKUP_KEY_PASSPHRASE': 'fixture-passphrase-at-least-24'}):
            folder = Path(name)
            with self.assertRaises(ValueError), patch.object(keys.backup, 'command', side_effect=AssertionError('GPG must not run')):
                keys.prepare(folder)
            self.assertFalse((folder / 'cloud-backup-gpg').exists())

    def test_lost_keyring_with_backup_never_rotates_key(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {'NT_BACKUP_KEY_PASSPHRASE': 'fixture-passphrase-at-least-24'}):
            folder = Path(name)
            private = folder / 'cloud-backup-private.asc'
            private.write_bytes(b'fixture-owned-private-export')
            with self.assertRaises(ValueError), patch.object(keys.backup, 'command', side_effect=AssertionError('GPG must not run')):
                keys.prepare(folder, create=True)
            self.assertEqual(private.read_bytes(), b'fixture-owned-private-export')
            self.assertFalse((folder / 'cloud-backup-gpg').exists())

    def test_empty_existing_keyring_with_backup_never_generates(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {'NT_BACKUP_KEY_PASSPHRASE': 'fixture-passphrase-at-least-24'}):
            folder = Path(name)
            (folder / 'cloud-backup-gpg').mkdir()
            public = folder / 'cloud-backup-public.asc'
            public.write_bytes(b'fixture-owned-public-export')
            with patch.object(keys.backup, 'command', return_value=b'') as command:
                with self.assertRaises(ValueError):
                    keys.prepare(folder, create=True)
                self.assertEqual(command.call_count, 1)
                self.assertIn('--list-secret-keys', command.call_args.args[0])
            self.assertEqual(public.read_bytes(), b'fixture-owned-public-export')


if __name__ == '__main__':
    unittest.main()
