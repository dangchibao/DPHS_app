import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BackupWorkflowGateTests(unittest.TestCase):
    def check_gate(self, first, second, expected):
        with tempfile.TemporaryDirectory(prefix='nt-workflow-') as folder:
            output, summary = Path(folder) / 'output', Path(folder) / 'summary'
            env = {**os.environ, 'GITHUB_OUTPUT': str(output),
                   'GITHUB_STEP_SUMMARY': str(summary)}
            for name, value in [('CLOUD_BACKUP_ENABLED', first),
                                ('R2_PRIVATE_BACKUP_CONFIRMED', second)]:
                env.pop(name, None)
                if value is not None:
                    env[name] = value
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('cloud_backup_gate.py'))],
                                    env=env, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(encoding='utf-8'), f'enabled={expected}\n')
            self.assertEqual(result.stdout, b'')
            if expected == 'false':
                self.assertIn('không tạo', summary.read_text(encoding='utf-8'))
            else:
                self.assertFalse(summary.exists())

    def test_missing_or_single_opt_in_never_enables_backup(self):
        for flags in [(None, None), ('true', None), (None, 'true'), ('false', 'true')]:
            with self.subTest(flags=flags):
                self.check_gate(*flags, 'false')

    def test_both_confirmations_enable_backup(self):
        self.check_gate('true', 'true', 'true')

    def test_nonliteral_flags_cannot_inject_workflow_outputs(self):
        self.check_gate('true\nenabled=true', 'true', 'false')


if __name__ == '__main__':
    unittest.main()
